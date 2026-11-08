import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/rankings_repository_impl.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/rankings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RankingsRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = RankingsRepositoryImpl(db, FixedClock(DateTime.utc(2026, 11, 4)));
  });
  tearDown(() => db.close());

  const first = DrinkRankings(
    overall: {'d1': 5, 'd2': 2},
    persons: {
      'p1': {'d1': 3},
    },
  );
  const second = DrinkRankings(
    overall: {'d2': 9},
    persons: {
      'p2': {'d2': 4},
    },
  );

  test('watch emits null before the first save', () async {
    expect(await repo.watch().first, isNull);
  });

  test('save then watch returns the rankings', () async {
    await repo.save(first);
    expect(await repo.watch().first, first);
  });

  test('a second save replaces the first', () async {
    await repo.save(first);
    await repo.save(second);
    expect(await repo.watch().first, second);
    expect(await db.select(db.rankingsCache).get(), hasLength(1));
  });

  test('clear drops the cached rankings and watch emits null', () async {
    await repo.save(first);
    final seen = <DrinkRankings?>[];
    final sub = repo.watch().listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await repo.clear();
    await pumpEventQueue();
    expect(seen, [first, null]);
    expect(await db.select(db.rankingsCache).get(), isEmpty);
  });
}
