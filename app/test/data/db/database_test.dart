import 'package:bar_tab/data/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a fresh schema v1 database matches the committed dump', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
  });

  test('a fresh schema v2 database matches the committed dump', () async {
    final connection = await verifier.startAt(2);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);
  });

  test('migrating v1 to v2 adds app_config and keeps existing rows', () async {
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    await old.customStatement(
      "INSERT INTO tabs (person_id, cents, fetched_at) VALUES ('p1', 5, '2026-11-02T18:30:15.000Z')",
    );
    await old.customStatement(
      "INSERT INTO bookings (id, person_id, drink_id, quantity, "
      "unit_price_cents, booked_at, status, included_in_tabs, created_at, "
      "updated_at) VALUES ('b1', 'p1', 'd1', 2, 250, "
      "'2026-11-02T18:30:15.000Z', 'queued', 0, '2026-11-02T18:30:15.000Z', "
      "'2026-11-02T18:30:15.000Z')",
    );
    await old.customStatement(
      "INSERT INTO catalog_cache (id, json, etag, saved_at) "
      "VALUES (1, '{}', 'e1', '2026-11-02T18:30:15.000Z')",
    );
    await old.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);
    expect((await db.select(db.tabs).getSingle()).personId, 'p1');
    expect((await db.select(db.bookings).getSingle()).id, 'b1');
    expect((await db.select(db.catalogCache).getSingle()).etag, 'e1');
    expect(await db.select(db.appConfig).get(), isEmpty);
  });

  test('UTC DateTime values round-trip as UTC', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final at = DateTime.utc(2026, 11, 2, 18, 30, 15);
    await db
        .into(db.tabs)
        .insert(TabsCompanion.insert(personId: 'p1', cents: 5, fetchedAt: at));
    final row = await db.select(db.tabs).getSingle();
    expect(row.fetchedAt, at);
    expect(row.fetchedAt.isUtc, isTrue);
  });

  test('catalog cache accepts only the single row id 1', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      db
          .into(db.catalogCache)
          .insert(
            CatalogCacheCompanion.insert(
              id: const Value(2),
              json: '{}',
              etag: 'e',
              savedAt: DateTime.utc(2026),
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });
}
