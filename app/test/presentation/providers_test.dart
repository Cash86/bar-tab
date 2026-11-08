import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/data/db/database.dart';

import 'package:bar_tab/data/repositories/booking_repository_impl.dart';
import 'package:bar_tab/data/repositories/rankings_repository_impl.dart';
import 'package:bar_tab/data/repositories/server_config_repository_impl.dart';
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
import 'package:http/http.dart' as http;

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

  group('re-pairing', () {
    const oldConfig = ServerConfig(
      baseUrl: 'https://old.example',
      deviceKey: 'old-key',
    );
    const newConfig = ServerConfig(
      baseUrl: 'https://new.example',
      deviceKey: 'new-key',
    );
    const rankings = DrinkRankings(
      overall: {'d1': 2},
      persons: {
        'p1': {'d1': 2},
      },
    );
    final clock = FixedClock(DateTime.utc(2026, 11, 2));
    late List<List<String>> postedToNew;

    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    Booking booking(String id, BookingStatus status) => Booking(
      id: id,
      personId: 'p1',
      drinkId: 'd1',
      quantity: 1,
      unitPriceCents: 150,
      bookedAt: DateTime.utc(2026, 11, 1, 20),
      status: status,
      includedInTabs: false,
    );

    setUp(() async {
      store.values.addAll({
        ServerConfigRepositoryImpl.baseUrlKey: oldConfig.baseUrl,
        ServerConfigRepositoryImpl.deviceKeyKey: oldConfig.deviceKey,
      });
      postedToNew = [];
      // The old server is gone; the new one answers like a real server.
      server.respond = (r) async {
        if (r.url.host != 'new.example') {
          throw http.ClientException('old server down');
        }
        final path = r.url.path.replaceFirst('/api/v1/', '');
        switch ('${r.method} $path') {
          case 'GET catalog':
            return catalogResponse();
          case 'POST bookings':
            final body = jsonDecode((r as http.Request).body) as Map;
            final ids = [
              for (final b in body['bookings'] as List)
                (b as Map)['id'] as String,
            ];
            postedToNew.add(ids);
            return json({
              'results': [
                for (final id in ids) {'id': id, 'status': 'accepted'},
              ],
            });
          case 'GET tabs':
            return json({
              'period_started_at': '2026-11-01T00:00:00Z',
              'tabs': {'p1': 900},
            });
          case 'GET rankings':
            return json({
              'overall': <String, int>{},
              'persons': <String, Object>{},
            });
        }
        return json({'detail': 'not_found'}, 404);
      };
      await BookingRepositoryImpl(db, clock).addAll([
        booking('queued', BookingStatus.queued),
        booking('failed', BookingStatus.rejected),
        booking('accepted', BookingStatus.accepted),
      ]);
      await TabsRepositoryImpl(db, clock).save({'p1': 500});
      await RankingsRepositoryImpl(db, clock).save(rankings);
      expect(await container.read(serverConfigProvider.future), oldConfig);
    });

    Future<Map<String, String>> bookingStatuses() async => {
      for (final row in await db.select(db.bookings).get()) row.id: row.status,
    };

    test('success replaces the config, clears tabs and rankings, '
        'keeps every booking', () async {
      final result = await container
          .read(pairingProvider)
          .pair(newConfig, repair: true);

      expect(result, PairingResult.success);
      expect(container.read(serverConfigProvider).value, newConfig);
      expect(
        store.values[ServerConfigRepositoryImpl.baseUrlKey],
        newConfig.baseUrl,
      );
      expect(await db.select(db.tabs).get(), isEmpty);
      expect(await db.select(db.rankingsCache).get(), isEmpty);
      expect(await bookingStatuses(), {
        'queued': 'queued',
        'failed': 'rejected',
        'accepted': 'accepted',
      });
    });

    for (final (name, config) in [
      (
        'unreachable',
        const ServerConfig(baseUrl: 'https://down.example', deviceKey: 'k'),
      ),
      (
        'typo',
        const ServerConfig(
          baseUrl: 'https://new.exampel',
          deviceKey: 'new-key',
        ),
      ),
    ]) {
      test('a failed repair ($name) changes nothing', () async {
        final catalogBefore = await db.select(db.catalogCache).get();
        final result = await container
            .read(pairingProvider)
            .pair(config, repair: true);

        expect(result, PairingResult.unreachable);
        expect(container.read(serverConfigProvider).value, oldConfig);
        expect(
          store.values[ServerConfigRepositoryImpl.baseUrlKey],
          oldConfig.baseUrl,
        );
        expect(await db.select(db.catalogCache).get(), catalogBefore);
        expect((await db.select(db.tabs).getSingle()).cents, 500);
        expect(await RankingsRepositoryImpl(db, clock).watch().first, rankings);
        expect(await bookingStatuses(), {
          'queued': 'queued',
          'failed': 'rejected',
          'accepted': 'accepted',
        });
      });
    }

    test('a rejected device key on repair changes nothing', () async {
      server.respond = (r) async => json({'detail': 'unauthorised'}, 401);
      final result = await container
          .read(pairingProvider)
          .pair(newConfig, repair: true);
      expect(result, PairingResult.unauthorised);
      expect(container.read(serverConfigProvider).value, oldConfig);
      expect((await db.select(db.tabs).getSingle()).cents, 500);
    });

    test(
      'after repair a queued booking is pushed once to the new api',
      () async {
        container.listen(syncServiceProvider, (_, _) {});
        await settle();
        expect(postedToNew, isEmpty);

        await container.read(pairingProvider).pair(newConfig, repair: true);
        await settle();
        await container.read(syncServiceProvider)!.syncNow();

        expect(postedToNew, [
          ['queued'],
        ]);
        expect(await bookingStatuses(), {
          'queued': 'accepted',
          'failed': 'rejected',
          'accepted': 'accepted',
        });
        // Refetched from the new server.
        expect((await db.select(db.tabs).getSingle()).cents, 900);
      },
    );
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

    test('loading until the first emission, then tab plus local', () async {
      final total = StreamController<int>();
      final c = ProviderContainer(
        overrides: [
          tabsRepositoryProvider.overrideWithValue(_FakeTabs(total.stream)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(runningTotalProvider('p1'), (_, _) {});
      expect(c.read(runningTotalProvider('p1')).isLoading, isTrue);

      total.add(800);
      await pump();
      expect(c.read(runningTotalProvider('p1')).value, 800);
      await total.close();
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

    test('running total never shows an intermediate value when a booking moves '
        'into the tab', () async {
      final tabs = TabsRepositoryImpl(db, FixedClock(DateTime.utc(2026)));
      final bookings = BookingRepositoryImpl(
        db,
        FixedClock(DateTime.utc(2026)),
      );
      await tabs.save({'p1': 300});
      await bookings.addAll([
        Booking(
          id: 'a',
          personId: 'p1',
          drinkId: 'd1',
          quantity: 1,
          unitPriceCents: 150,
          bookedAt: DateTime.utc(2026, 11, 2, 18),
          status: BookingStatus.accepted,
          includedInTabs: false,
        ),
      ]);
      final seen = <int>[];
      container.listen(runningTotalProvider('p1'), (_, next) {
        final v = next.value;
        if (v != null) seen.add(v);
      }, fireImmediately: true);
      await pump();
      expect(seen.last, 450);

      // The same transaction the sync runs when the server tab absorbs it.
      await db.transaction(() async {
        await tabs.save({'p1': 450});
        await bookings.markIncludedInTabs({'a'});
      });
      await pump();

      expect(seen, isNotEmpty);
      expect(seen.toSet(), {450});
    });

    test('dropping the last listener cancels the source stream', () async {
      var cancelled = false;
      final total = StreamController<int>(onCancel: () => cancelled = true);
      final c = ProviderContainer(
        overrides: [
          tabsRepositoryProvider.overrideWithValue(_FakeTabs(total.stream)),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(runningTotalProvider('p1'), (_, _) {});
      await pump();
      sub.close();
      c.dispose();
      await pump();
      expect(cancelled, isTrue);
    });
  });
}

class _FakeTabs implements TabsRepository {
  _FakeTabs(this._stream);
  final Stream<int> _stream;
  @override
  Stream<int> watchTab(String personId) => throw UnimplementedError();
  @override
  Stream<int> watchRunningTotal(String personId) => _stream;
  @override
  Future<void> save(Map<String, int> tabs) => throw UnimplementedError();
  @override
  Future<void> clear() => throw UnimplementedError();
}
