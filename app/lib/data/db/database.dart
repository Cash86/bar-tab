import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// The whole catalog as JSON in a single row (small, only ever read whole).
class CatalogCache extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get json => text()();
  TextColumn get etag => text()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}

@TableIndex(name: 'bookings_status', columns: {#status})
@TableIndex(
  name: 'bookings_person_included',
  columns: {#personId, #includedInTabs},
)
@DataClassName('BookingRow')
class Bookings extends Table {
  TextColumn get id => text()();
  TextColumn get personId => text()();
  TextColumn get drinkId => text()();
  IntColumn get quantity => integer()();
  IntColumn get unitPriceCents => integer()();
  DateTimeColumn get bookedAt => dateTime()();

  /// A `BookingStatus` name.
  TextColumn get status => text()();
  BoolColumn get includedInTabs =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tabs extends Table {
  TextColumn get personId => text()();
  IntColumn get cents => integer()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {personId};
}

/// App-private key-value settings (server URL, device key).
class AppConfig extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [CatalogCache, Bookings, Tabs, AppConfig])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(appConfig);
    },
  );
}

/// Opens the production database in the app documents directory.
Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = p.join(dir.path, 'bar_tab.sqlite');
  return AppDatabase(NativeDatabase.createInBackground(File(file)));
}
