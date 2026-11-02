import '../db/database.dart';
import 'server_config_repository_impl.dart';

/// [ConfigStore] backed by the `app_config` table of the app database.
class DriftConfigStore implements ConfigStore {
  DriftConfigStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.appConfig,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> write(String key, String value) => _db
      .into(_db.appConfig)
      .insertOnConflictUpdate(
        AppConfigCompanion.insert(key: key, value: value),
      );

  @override
  Future<void> delete(String key) =>
      (_db.delete(_db.appConfig)..where((t) => t.key.equals(key))).go();
}
