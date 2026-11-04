import 'package:bar_tab/data/db/database.dart';
import 'dart:async';

import 'package:bar_tab/data/repositories/booking_repository_impl.dart';
import 'package:bar_tab/data/repositories/rankings_repository_impl.dart';
import 'package:bar_tab/data/repositories/tabs_repository_impl.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/rankings.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fakes.dart';

void main() {
  late AppDatabase db;
  late FakeApiServer server;
  late FakeConfigStore store;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    server = FakeApiServer();
    store = FakeConfigStore();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        configStoreProvider.overrideWithValue(store),
        httpClientProvider.overrideWithValue(server.client),
        clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 11, 2))),
        // Long enough that the periodic timer never fires during a test.
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('rankingsProvider emits what the repository holds', () async {
    final seen = <DrinkRankings?>[];
    container.listen(rankingsProvider, (_, next) {
      seen.add(next.value);
    }, fireImmediately: true);
    await settle();
    expect(seen.last, isNull);

    const rankings = DrinkRankings(
      overall: {'d1': 2},
      persons: {
        'p1': {'d1': 2},
      },
    );
    await RankingsRepositoryImpl(
      db,
      FixedClock(DateTime.utc(2026, 11, 2)),
    ).save(rankings);
    await settle();

    expect(seen.last, rankings);
  });

  test('no sync service or api while unconfigured', () async {
    await container.read(serverConfigProvider.future);
    expect(container.read(apiProvider), isNull);
    expect(container.read(syncServiceProvider), isNull);
  });

  test('re-pairing rebuilds api and sync service with the new key', () async {
    await container.read(serverConfigProvider.future);
    container.listen(syncServiceProvider, (_, _) {});

    await container
        .read(serverConfigProvider.notifier)
        .save(const ServerConfig(baseUrl: 'https://a.example', deviceKey: 'A'));
    final serviceA = container.read(syncServiceProvider)!;
    await settle();
    expect(server.authHeaders, isNotEmpty);
    expect(server.authHeaders.toSet(), {'Bearer A'});

    await container
        .read(serverConfigProvider.notifier)
        .save(const ServerConfig(baseUrl: 'https://b.example', deviceKey: 'B'));
    final serviceB = container.read(syncServiceProvider)!;
    expect(serviceB, isNot(same(serviceA)));
    await settle();
    final afterRepair = server.requests.length;
    expect(server.authHeaders.last, 'Bearer B');
    expect(server.requests.last.url.host, 'b.example');

    // The old service is disposed: it no longer talks to the server.
    await serviceA.syncNow();
    expect(server.requests.length, afterRepair);
    await serviceB.syncNow();
    expect(server.requests.length, greaterThan(afterRepair));
    expect(server.authHeaders.last, 'Bearer B');
  });

  group('runningTotalProvider', () {
    Booking booking(String id, BookingStatus status, {String person = 'p1'}) =>
        Booking(
          id: id,
          personId: person,
          drinkId: 'd1',
          quantity: 2,
          unitPriceCents: 150,
          bookedAt: DateTime.utc(2026, 11, 2, 18),
          status: status,
          includedInTabs: false,
        );

    Future<void> pump() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    test('loading until both sources emitted, then tab plus local', () async {
      final tabs = StreamController<int>();
      final bookings = StreamController<List<Booking>>();
      final c = ProviderContainer(
        overrides: [
          tabsRepositoryProvider.overrideWithValue(_FakeTabs(tabs.stream)),
          bookingRepositoryProvider.overrideWithValue(
            _FakeBookings(bookings.stream),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(runningTotalProvider('p1'), (_, _) {});
      expect(c.read(runningTotalProvider('p1')).isLoading, isTrue);

      tabs.add(500);
      await pump();
      expect(c.read(runningTotalProvider('p1')).isLoading, isTrue);

      bookings.add([booking('a', BookingStatus.queued)]);
      await pump();
      expect(c.read(runningTotalProvider('p1')).value, 800);
      await tabs.close();
      await bookings.close();
    });

    test(
      'follows new bookings and tab changes; rejected is excluded',
      () async {
        final bookings = BookingRepositoryImpl(
          db,
          FixedClock(DateTime.utc(2026)),
        );
        final tabs = TabsRepositoryImpl(db, FixedClock(DateTime.utc(2026)));
        container.listen(runningTotalProvider('p1'), (_, _) {});
        await pump();
        expect(container.read(runningTotalProvider('p1')).value, 0);

        await bookings.addAll([booking('a', BookingStatus.queued)]);
        await pump();
        expect(container.read(runningTotalProvider('p1')).value, 300);

        await bookings.addAll([booking('r', BookingStatus.rejected)]);
        await pump();
        expect(container.read(runningTotalProvider('p1')).value, 300);

        await tabs.save({'p1': 1000});
        await pump();
        expect(container.read(runningTotalProvider('p1')).value, 1300);
      },
    );

    test('dropping the last listener cancels both source streams', () async {
      var tabsCancelled = false;
      var bookingsCancelled = false;
      final tabs = StreamController<int>(onCancel: () => tabsCancelled = true);
      final bookings = StreamController<List<Booking>>(
        onCancel: () => bookingsCancelled = true,
      );
      final c = ProviderContainer(
        overrides: [
          tabsRepositoryProvider.overrideWithValue(_FakeTabs(tabs.stream)),
          bookingRepositoryProvider.overrideWithValue(
            _FakeBookings(bookings.stream),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(runningTotalProvider('p1'), (_, _) {});
      await pump();
      sub.close();
      c.dispose();
      await pump();
      expect(tabsCancelled, isTrue);
      expect(bookingsCancelled, isTrue);
    });
  });
}

class _FakeTabs implements TabsRepository {
  _FakeTabs(this._stream);
  final Stream<int> _stream;
  @override
  Stream<int> watchTab(String personId) => _stream;
  @override
  Future<void> save(Map<String, int> tabs) => throw UnimplementedError();
}

class _FakeBookings implements BookingRepository {
  _FakeBookings(this._stream);
  final Stream<List<Booking>> _stream;
  @override
  Stream<List<Booking>> watchNotIncluded(String personId) => _stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
