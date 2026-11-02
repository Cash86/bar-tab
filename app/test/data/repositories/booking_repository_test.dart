import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/booking_repository_impl.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Booking booking(
  String id, {
  String personId = 'p1',
  int minute = 0,
  BookingStatus status = BookingStatus.queued,
  DateTime? holdUntil,
}) => Booking(
  id: id,
  personId: personId,
  drinkId: 'd1',
  quantity: 2,
  unitPriceCents: 150,
  bookedAt: DateTime.utc(2026, 11, 2, 18, minute),
  status: status,
  includedInTabs: false,
  holdUntil: holdUntil,
);

void main() {
  late AppDatabase db;
  late BookingRepositoryImpl repo;
  late FixedClock clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 11, 2, 19));
    repo = BookingRepositoryImpl(db, clock);
  });
  tearDown(() => db.close());

  test('queued returns oldest bookedAt first and honours limit', () async {
    await repo.addAll([
      booking('c', minute: 30),
      booking('a', minute: 10),
      booking('b', minute: 20),
      booking('x', minute: 1, status: BookingStatus.accepted),
    ]);
    expect((await repo.queued(limit: 10)).map((b) => b.id), ['a', 'b', 'c']);
    expect((await repo.queued(limit: 2)).map((b) => b.id), ['a', 'b']);
  });

  test('stored booking round-trips with UTC bookedAt', () async {
    await repo.addAll([booking('a', minute: 10)]);
    final got = (await repo.queued(limit: 1)).single;
    expect(got, booking('a', minute: 10));
    expect(got.bookedAt.isUtc, isTrue);
  });

  test('applyResults stores the given domain statuses', () async {
    await repo.addAll([booking('a'), booking('b'), booking('c'), booking('d')]);
    await repo.applyResults({
      'a': BookingStatus.accepted,
      'b': BookingStatus.rejected,
      'c': BookingStatus.conflict,
    });
    final rows = await db.select(db.bookings).get();
    final byId = {for (final r in rows) r.id: r.status};
    expect(byId, {
      'a': 'accepted',
      'b': 'rejected',
      'c': 'conflict',
      'd': 'queued',
    });
    expect((await repo.queued(limit: 10)).map((b) => b.id), ['d']);
  });

  test('applyResults updates updatedAt from the clock', () async {
    await repo.addAll([booking('a')]);
    clock.advance(const Duration(minutes: 5));
    await repo.applyResults({'a': BookingStatus.accepted});
    final row = await db.select(db.bookings).getSingle();
    expect(row.createdAt, DateTime.utc(2026, 11, 2, 19));
    expect(row.updatedAt, DateTime.utc(2026, 11, 2, 19, 5));
  });

  test('watchNotIncluded emits after insert and markIncludedInTabs', () async {
    final emissions = <List<String>>[];
    final sub = repo
        .watchNotIncluded('p1')
        .listen((l) => emissions.add(l.map((b) => b.id).toList()));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(emissions.last, isEmpty);

    await repo.addAll([
      booking('a', minute: 1),
      booking('b', minute: 2),
      booking('other', personId: 'p2'),
    ]);
    await pumpEventQueue();
    expect(emissions.last, unorderedEquals(['a', 'b']));

    await repo.markIncludedInTabs({'a'});
    await pumpEventQueue();
    expect(emissions.last, ['b']);
  });

  test('watchNotIncluded includes all statuses', () async {
    await repo.addAll([
      booking('a'),
      booking('b', status: BookingStatus.rejected),
    ]);
    final got = await repo.watchNotIncluded('p1').first;
    expect(got.map((b) => b.id), unorderedEquals(['a', 'b']));
  });

  test('watchCounts reflects queued and failed', () async {
    final emissions = <SyncCounts>[];
    final sub = repo.watchCounts().listen(emissions.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(emissions.last, const SyncCounts(queued: 0, failed: 0));

    await repo.addAll([booking('a'), booking('b'), booking('c'), booking('d')]);
    await repo.applyResults({
      'b': BookingStatus.rejected,
      'c': BookingStatus.conflict,
      'd': BookingStatus.accepted,
    });
    await pumpEventQueue();
    expect(emissions.last, const SyncCounts(queued: 1, failed: 2));
  });

  test(
    'addAll with an existing id throws and rolls back the whole batch',
    () async {
      await repo.addAll([booking('a', minute: 1)]);
      await expectLater(
        repo.addAll([booking('b', minute: 2), booking('a', minute: 55)]),
        throwsA(isA<SqliteException>()),
      );
      final rows = await db.select(db.bookings).get();
      expect(rows.map((r) => r.id), ['a']);
      expect(rows.single.bookedAt, DateTime.utc(2026, 11, 2, 18, 1));
    },
  );

  test('applyResults ignores unknown ids and an empty map', () async {
    await repo.addAll([booking('a')]);
    await repo.applyResults({'ghost': BookingStatus.accepted});
    await repo.applyResults({});
    final rows = await db.select(db.bookings).get();
    expect(rows.map((r) => r.id), ['a']);
    expect(rows.single.status, 'queued');
  });

  test('markIncludedInTabs touches only the given ids', () async {
    await repo.addAll([
      booking('a'),
      booking('b'),
      booking('c', personId: 'p2'),
    ]);
    await repo.markIncludedInTabs({'a', 'ghost'});
    await repo.markIncludedInTabs({});
    final rows = await db.select(db.bookings).get();
    expect(
      {for (final r in rows) r.id: r.includedInTabs},
      {'a': true, 'b': false, 'c': false},
    );
  });

  test(
    'acceptedNotIncludedIds returns only accepted, not yet included',
    () async {
      await repo.addAll([
        booking('a', status: BookingStatus.accepted),
        booking('b', status: BookingStatus.accepted),
        booking('c'),
        booking('d', status: BookingStatus.rejected),
        booking('e', status: BookingStatus.conflict),
        booking('f', personId: 'p2', status: BookingStatus.accepted),
      ]);
      await repo.markIncludedInTabs({'b'});
      expect(await repo.acceptedNotIncludedIds(), {'a', 'f'});
    },
  );

  group('undo window', () {
    // The clock starts at 19:00; held bookings are held until 19:00:15.
    final until = DateTime.utc(2026, 11, 2, 19, 0, 15);

    test('holdUntil round-trips', () async {
      await repo.addAll([booking('a', holdUntil: until)]);
      final got = (await repo.watchNotIncluded('p1').first).single;
      expect(got, booking('a', holdUntil: until));
      expect(got.holdUntil!.isUtc, isTrue);
    });

    test('queued excludes held bookings until the hold expires', () async {
      await repo.addAll([
        booking('free', minute: 1),
        booking('held', minute: 2, holdUntil: until),
      ]);
      expect((await repo.queued()).map((b) => b.id), ['free']);
      clock.advance(const Duration(seconds: 14, milliseconds: 999));
      expect((await repo.queued()).map((b) => b.id), ['free']);
      clock.advance(const Duration(milliseconds: 1));
      expect((await repo.queued()).map((b) => b.id), ['free', 'held']);
    });

    test('held bookings count in the not-included list at once', () async {
      await repo.addAll([booking('held', holdUntil: until)]);
      final got = await repo.watchNotIncluded('p1').first;
      expect(got.map((b) => b.id), ['held']);
    });

    test('undo inside the window deletes the bookings', () async {
      await repo.addAll([
        booking('a', holdUntil: until),
        booking('b', holdUntil: until),
        booking('other', holdUntil: until),
      ]);
      clock.advance(const Duration(seconds: 14));
      expect(await repo.undoHeld({'a', 'b'}), isTrue);
      final rows = await db.select(db.bookings).get();
      expect(rows.map((r) => r.id), ['other']);
    });

    test('undo after the hold expired deletes nothing', () async {
      await repo.addAll([booking('a', holdUntil: until)]);
      clock.advance(const Duration(seconds: 15));
      expect(await repo.undoHeld({'a'}), isFalse);
      expect((await db.select(db.bookings).get()).map((r) => r.id), ['a']);
    });

    test('undo after a sync pushed the bookings is impossible', () async {
      await repo.addAll([booking('a', holdUntil: until)]);
      // Only reachable after the hold, but even a pushed held booking must
      // never be deleted.
      await repo.applyResults({'a': BookingStatus.accepted});
      expect(await repo.undoHeld({'a'}), isFalse);
      final row = await db.select(db.bookings).getSingle();
      expect(row.status, 'accepted');
    });

    test('a partly matching set deletes nothing', () async {
      await repo.addAll([
        booking('held', holdUntil: until),
        booking('free'),
        booking('expired', holdUntil: DateTime.utc(2026, 11, 2, 18, 59)),
      ]);
      for (final ids in [
        {'held', 'free'},
        {'held', 'expired'},
        {'held', 'ghost'},
      ]) {
        expect(await repo.undoHeld(ids), isFalse, reason: '$ids');
      }
      expect(
        (await db.select(db.bookings).get()).map((r) => r.id),
        unorderedEquals(['held', 'free', 'expired']),
      );
    });

    test('undo of an empty set does nothing', () async {
      await repo.addAll([booking('a', holdUntil: until)]);
      expect(await repo.undoHeld({}), isFalse);
      expect(await db.select(db.bookings).get(), hasLength(1));
    });
  });
}
