import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/clock.dart';
import '../../domain/rankings.dart';
import '../../domain/repositories.dart';
import '../api/dto.dart';
import '../api/mappers.dart';
import '../db/database.dart';

class RankingsRepositoryImpl implements RankingsRepository {
  RankingsRepositoryImpl(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<void> save(DrinkRankings rankings) async {
    await _db
        .into(_db.rankingsCache)
        .insertOnConflictUpdate(
          RankingsCacheCompanion.insert(
            id: const Value(1),
            json: jsonEncode(rankingsToDto(rankings).toJson()),
            savedAt: _clock.now(),
          ),
        );
  }

  @override
  Stream<DrinkRankings?> watch() {
    return _db.select(_db.rankingsCache).watchSingleOrNull().map((row) {
      if (row == null) return null;
      final json = jsonDecode(row.json) as Map<String, dynamic>;
      return rankingsFromDto(RankingsDto.fromJson(json));
    });
  }
}
