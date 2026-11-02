import 'package:bar_tab/data/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a fresh schema v1 database matches the committed dump', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
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
      throwsA(isA<Exception>()),
    );
  });
}
