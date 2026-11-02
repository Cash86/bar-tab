import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/catalog.dart';
import '../../domain/clock.dart';
import '../../domain/repositories.dart';
import '../api/dto.dart';
import '../api/mappers.dart';
import '../db/database.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<Catalog?> cached() async {
    final row = await _db.select(_db.catalogCache).getSingleOrNull();
    if (row == null) return null;
    final json = jsonDecode(row.json) as Map<String, dynamic>;
    return catalogFromDto(CatalogDto.fromJson(json));
  }

  @override
  Future<void> save(Catalog catalog) async {
    await _db
        .into(_db.catalogCache)
        .insertOnConflictUpdate(
          CatalogCacheCompanion.insert(
            id: const Value(1),
            json: jsonEncode(catalogToDto(catalog).toJson()),
            etag: catalog.etag,
            savedAt: _clock.now(),
          ),
        );
  }
}
