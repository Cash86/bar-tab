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

  static Booking _toDomain(BookingRow r) => Booking(
    id: r.id,
    personId: r.personId,
    drinkId: r.drinkId,
    quantity: r.quantity,
    unitPriceCents: r.unitPriceCents,
    bookedAt: r.bookedAt,
    status: BookingStatus.values.byName(r.status),
    includedInTabs: r.includedInTabs,
  );

  @override
  Future<void> addAll(List<Booking> bookings) async {
    final now = _clock.now();
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
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
  }

  @override
  Future<List<Booking>> queued({int limit = 100}) async {
    final q = _db.select(_db.bookings)
      ..where((t) => t.status.equals(BookingStatus.queued.name))
      ..orderBy([(t) => OrderingTerm.asc(t.bookedAt)])
      ..limit(limit);
    return (await q.get()).map(_toDomain).toList();
  }

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
  Stream<List<Booking>> watchNotIncluded(String personId) {
    final q = _db.select(_db.bookings)
      ..where(
        (t) => t.personId.equals(personId) & t.includedInTabs.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.bookedAt)]);
    return q.watch().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Stream<SyncCounts> watchCounts() {
    final queued = _db.bookings.id.count(
      filter: _db.bookings.status.equals(BookingStatus.queued.name),
    );
    final failed = _db.bookings.id.count(
      filter: _db.bookings.status.isIn([
        BookingStatus.rejected.name,
        BookingStatus.conflict.name,
      ]),
    );
    final q = _db.selectOnly(_db.bookings)..addColumns([queued, failed]);
    return q.watchSingle().map(
      (row) => SyncCounts(queued: row.read(queued)!, failed: row.read(failed)!),
    );
  }
}
