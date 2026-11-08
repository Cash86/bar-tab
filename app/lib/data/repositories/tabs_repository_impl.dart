import 'package:drift/drift.dart';

import '../../domain/booking.dart';
import '../../domain/clock.dart';
import '../../domain/running_total.dart';
import '../../domain/repositories.dart';
import '../db/database.dart';
import 'booking_repository_impl.dart';

class TabsRepositoryImpl implements TabsRepository {
  TabsRepositoryImpl(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<void> save(Map<String, int> tabs) async {
    final now = _clock.now();
    await _db.transaction(() async {
      await _db.delete(_db.tabs).go();
      await _db.batch((b) {
        b.insertAll(_db.tabs, [
          for (final e in tabs.entries)
            TabsCompanion.insert(
              personId: e.key,
              cents: e.value,
              fetchedAt: now,
            ),
        ]);
      });
    });
  }

  @override
  Future<void> clear() => _db.delete(_db.tabs).go();

  @override
  Stream<int> watchTab(String personId) {
    final q = _db.select(_db.tabs)..where((t) => t.personId.equals(personId));
    return q.watchSingleOrNull().map((r) => r?.cents ?? 0);
  }

  @override
  Stream<int> watchRunningTotal(String personId) {
    // One statement over both tables, so a transaction touching both (the
    // sync) is seen whole. The tab is a scalar subquery; bookings are left
    // joined (a person without open bookings yields one row with a NULL id).
    return _db
        .customSelect(
          'SELECT (SELECT COALESCE(SUM(cents), 0) FROM tabs '
          'WHERE person_id = ?1) AS tab_cents, b.* '
          'FROM (SELECT 1) LEFT JOIN bookings b '
          'ON b.person_id = ?1 AND b.included_in_tabs = 0',
          variables: [Variable<String>(personId)],
          readsFrom: {_db.tabs, _db.bookings},
        )
        .watch()
        .map((rows) {
          final bookings = <Booking>[];
          for (final r in rows) {
            if (r.data['id'] == null) continue;
            bookings.add(
              BookingRepositoryImpl.toDomain(_db.bookings.map(r.data)),
            );
          }
          return runningTotalCents(
            serverTabCents: rows.first.read<int>('tab_cents'),
            localBookings: bookings,
          );
        });
  }
}
