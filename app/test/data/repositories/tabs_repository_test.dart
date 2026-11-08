import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/tabs_repository_impl.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TabsRepositoryImpl repo;
  late FixedClock clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 11, 2, 12));
    repo = TabsRepositoryImpl(db, clock);
  });
  tearDown(() => db.close());

  test('watchTab emits 0 for an unknown person', () async {
    expect(await repo.watchTab('p1').first, 0);
  });

  test('save replaces all rows', () async {
    await repo.save({'p1': 500, 'p2': 700});
    expect(await repo.watchTab('p1').first, 500);
    await repo.save({'p2': 100});
    expect(await repo.watchTab('p1').first, 0);
    expect(await repo.watchTab('p2').first, 100);
    expect(await db.select(db.tabs).get(), hasLength(1));
  });

  test('save stamps fetchedAt and watchTab re-emits on save', () async {
    final values = <int>[];
    final sub = repo.watchTab('p1').listen(values.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await repo.save({'p1': 250});
    await pumpEventQueue();
    expect(values, [0, 250]);
    expect(
      (await db.select(db.tabs).getSingle()).fetchedAt,
      DateTime.utc(2026, 11, 2, 12),
    );
  });

  test('clear removes every cached tab and re-emits', () async {
    await repo.save({'p1': 500, 'p2': 700});
    final values = <int>[];
    final sub = repo.watchTab('p1').listen(values.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await repo.clear();
    await pumpEventQueue();
    expect(values, [500, 0]);
    expect(await db.select(db.tabs).get(), isEmpty);
  });
}
