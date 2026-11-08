import '../../domain/clock.dart';
import '../../domain/repositories.dart';
import '../db/database.dart';

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
}
