import 'dart:async';

import 'package:drift/drift.dart';

import '../../domain/booking.dart';
import '../../domain/clock.dart';
import '../../domain/repositories.dart';
import '../../domain/sync_state.dart';
import '../db/database.dart';

class BookingRepositoryImpl implements BookingRepository {
  BookingRepositoryImpl(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  /// Held: `holdUntil` lies in the future, but no further than one undo
  /// window. A hold further out can only come from the clock stepping back
  /// after the commit; it is ignored, so such bookings are not stuck for the
  /// length of the jump. (A sub-second backward step while a push is in
  /// flight could still let an undo delete a booking being sent; excluding
  /// that would need a "sending" mark. Accepted.)
  static bool _isHeld(DateTime? holdUntil, DateTime now) =>
      holdUntil != null &&
      holdUntil.isAfter(now) &&
      !holdUntil.isAfter(now.add(kUndoWindow));

  static Expression<bool> _heldExpr($BookingsTable t, DateTime now) =>
      t.holdUntil.isBiggerThanValue(now) &
      t.holdUntil.isSmallerOrEqualValue(now.add(kUndoWindow));

  static Booking toDomain(BookingRow r) => Booking(
    id: r.id,
    personId: r.personId,
    drinkId: r.drinkId,
    quantity: r.quantity,
    unitPriceCents: r.unitPriceCents,
    bookedAt: r.bookedAt,
    status: BookingStatus.values.byName(r.status),
    includedInTabs: r.includedInTabs,
    holdUntil: r.holdUntil,
  );

  @override
  Future<void> addAll(List<Booking> bookings) async {
    final now = _clock.now();
    await _db.transaction(() async {
      await _db.batch((b) {
        b.insertAll(_db.bookings, [
          for (final x in bookings)
            BookingsCompanion.insert(
              id: x.id,
              personId: x.personId,
              drinkId: x.drinkId,
              quantity: x.quantity,
              unitPriceCents: x.unitPriceCents,
              bookedAt: x.bookedAt.toUtc(),
              status: x.status.name,
              includedInTabs: Value(x.includedInTabs),
              holdUntil: Value(x.holdUntil?.toUtc()),
              createdAt: now,
              updatedAt: now,
            ),
        ]);
      });
    });
  }

  @override
  Future<List<Booking>> queued({int limit = 100}) async {
    final now = _clock.now();
    final q = _db.select(_db.bookings)
      ..where(
        (t) =>
            t.status.equals(BookingStatus.queued.name) &
            (t.holdUntil.isNull() | _heldExpr(t, now).not()),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.bookedAt)])
      ..limit(limit);
    return (await q.get()).map(toDomain).toList();
  }

  @override
  Future<bool> undoHeld(Set<String> ids) async {
    if (ids.isEmpty) return false;
    final now = _clock.now();
    // One transaction: a sync marking them accepted cannot slip in between
    // the check and the delete.
    return _db.transaction(() async {
      Expression<bool> undoable($BookingsTable t) =>
          t.id.isIn(ids) &
          t.status.equals(BookingStatus.queued.name) &
          _heldExpr(t, now);
      final count = _db.bookings.id.count(filter: undoable(_db.bookings));
      final q = _db.selectOnly(_db.bookings)..addColumns([count]);
      if ((await q.getSingle()).read(count) != ids.length) return false;
      await (_db.delete(_db.bookings)..where(undoable)).go();
      return true;
    });
  }

  @override
  Future<void> releaseHolds() =>
      (_db.update(_db.bookings)..where(
            (t) =>
                t.status.equals(BookingStatus.queued.name) &
                t.holdUntil.isNotNull(),
          ))
          .write(const BookingsCompanion(holdUntil: Value(null)));

  @override
  Future<void> applyResults(Map<String, BookingStatus> results) async {
    final now = _clock.now();
    await _db.transaction(() async {
      for (final e in results.entries) {
        await (_db.update(
          _db.bookings,
        )..where((t) => t.id.equals(e.key))).write(
          BookingsCompanion(status: Value(e.value.name), updatedAt: Value(now)),
        );
      }
    });
  }

  @override
  Future<void> markIncludedInTabs(Set<String> ids) async {
    final now = _clock.now();
    await (_db.update(_db.bookings)..where((t) => t.id.isIn(ids))).write(
      BookingsCompanion(
        includedInTabs: const Value(true),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<Set<String>> acceptedNotIncludedIds() async {
    final q = _db.selectOnly(_db.bookings)
      ..addColumns([_db.bookings.id])
      ..where(
        _db.bookings.status.equals(BookingStatus.accepted.name) &
            _db.bookings.includedInTabs.equals(false),
      );
    return {for (final row in await q.get()) row.read(_db.bookings.id)!};
  }

  @override
  Stream<List<Booking>> watchNotIncluded(String personId) {
    final q = _db.select(_db.bookings)
      ..where(
        (t) => t.personId.equals(personId) & t.includedInTabs.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.bookedAt)]);
    return q.watch().map((rows) => rows.map(toDomain).toList());
  }

  /// Held bookings are not counted as queued (they are not waiting for the
  /// server yet); the counts are re-emitted when the next hold expires.
  @override
  Stream<SyncCounts> watchCounts() {
    final status = _db.bookings.status;
    final holdUntil = _db.bookings.holdUntil;
    final rows =
        (_db.selectOnly(_db.bookings)
              ..addColumns([status, holdUntil])
              ..where(status.equals(BookingStatus.accepted.name).not()))
            .watch()
            .map(
              (rs) => [
                for (final r in rs) (r.read(status)!, r.read(holdUntil)),
              ],
            );
    return Stream.multi((listener) {
      List<(String, DateTime?)>? latest;
      Timer? nextExpiry;
      void emit() {
        nextExpiry?.cancel();
        nextExpiry = null;
        final current = latest;
        if (current == null) return;
        final now = _clock.now();
        var queued = 0;
        var failed = 0;
        DateTime? soonest;
        for (final (s, hold) in current) {
          if (s != BookingStatus.queued.name) {
            failed++;
          } else if (_isHeld(hold, now)) {
            if (soonest == null || hold!.isBefore(soonest)) soonest = hold;
          } else {
            queued++;
          }
        }
        if (soonest != null) nextExpiry = Timer(soonest.difference(now), emit);
        listener.add(SyncCounts(queued: queued, failed: failed));
      }

      final sub = rows.listen((rs) {
        latest = rs;
        emit();
      }, onError: listener.addError);
      listener.onCancel = () {
        nextExpiry?.cancel();
        return sub.cancel();
      };
    });
  }
}
