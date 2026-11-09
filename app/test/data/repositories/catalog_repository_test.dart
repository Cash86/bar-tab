import 'dart:convert';

import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/data/api/mappers.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/catalog_repository_impl.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/catalog_fixture.dart';

void main() {
  late AppDatabase db;
  late CatalogRepositoryImpl repo;
  late FixedClock clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 11, 2, 12));
    repo = CatalogRepositoryImpl(db, clock);
  });
  tearDown(() => db.close());

  final catalog = catalogFromDto(CatalogDto.fromJson(catalogFixtureJson));

  test('cached is null before any save', () async {
    expect(await repo.cached(), isNull);
  });

  test('save then cached round-trips the catalog including etag', () async {
    await repo.save(catalog);
    expect(await repo.cached(), catalog);
    expect((await repo.cached())!.etag, 'abc123');
  });

  test('a cache written before is_keg existed reads as no keg', () async {
    final json = jsonDecode(jsonEncode(catalogFixtureJson)) as Map;
    for (final d in json['drinks'] as List) {
      (d as Map).remove('is_keg');
    }
    await db
        .into(db.catalogCache)
        .insert(
          CatalogCacheCompanion.insert(
            id: const Value(1),
            json: jsonEncode(json),
            etag: 'old',
            savedAt: clock.now(),
          ),
        );
    final cached = await repo.cached();
    expect(cached!.drinks, isNotEmpty);
    expect(cached.drinks.every((d) => !d.isKeg), isTrue);
  });

  test('a second save replaces the first and stamps savedAt', () async {
    await repo.save(catalog);
    clock.advance(const Duration(hours: 1));
    await repo.save(catalog.copyWith(etag: 'zzz'));
    expect((await repo.cached())!.etag, 'zzz');
    final rows = await db.select(db.catalogCache).get();
    expect(rows, hasLength(1));
    expect(rows.single.etag, 'zzz');
    expect(rows.single.savedAt, DateTime.utc(2026, 11, 2, 13));
  });
}
