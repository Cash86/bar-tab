import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bar_tab/data/api/api_client.dart';
import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/data/api/mappers.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/booking_repository_impl.dart';
import 'package:bar_tab/data/repositories/catalog_repository_impl.dart';
import 'package:bar_tab/data/repositories/tabs_repository_impl.dart';
import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import '../../fixtures/catalog_fixture.dart';

/// Scripted stand-in for the bar-tab server behind a [MockClient].
class FakeServer {
  /// Every request, as "METHOD path".
  final requests = <String>[];

  /// Booking ids of each POST /bookings, in order.
  final postBatches = <List<String>>[];

  /// Wire status per booking id; unknown ids are accepted.
  final resultFor = <String, String>{};

  /// When set, POST /bookings answers with these ids (all accepted)
  /// instead of the posted ones.
  List<String>? resultIdsOverride;

  /// Throw a SocketException for every request.
  bool offline = false;

  /// Answer every request with this status and an error body.
  int? forcedStatus;

  Map<String, int> tabs = {'p1': 1234};
  Map<String, dynamic> catalog = catalogFixtureJson;

  /// When set, GET /tabs waits for it before answering.
  Completer<void>? tabsGate;
  final tabsRequested = Completer<void>();

  /// If-None-Match headers seen on GET /catalog.
  final catalogEtagsSent = <String?>[];

  late final http.Client client = MockClient(_handle);

  int count(String request) => requests.where((r) => r == request).length;

  Future<http.Response> _handle(http.Request r) async {
    final path = r.url.path.replaceFirst('/api/v1/', '');
    requests.add('${r.method} $path');
    if (offline) throw const SocketException('unreachable');
    if (forcedStatus != null) {
      return _json({'detail': 'nope'}, forcedStatus!);
    }
    switch ('${r.method} $path') {
      case 'POST bookings':
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final ids = [
          for (final b in body['bookings'] as List<dynamic>)
            (b as Map<String, dynamic>)['id'] as String,
        ];
        postBatches.add(ids);
        final resultIds = resultIdsOverride ?? ids;
        return _json({
          'results': [
            for (final id in resultIds)
              {
                'id': id,
                'status': resultFor[id] ?? 'accepted',
                if (resultFor[id] == 'rejected') 'reason': 'unknown_drink',
              },
          ],
        });
      case 'GET tabs':
        if (!tabsRequested.isCompleted) tabsRequested.complete();
        await tabsGate?.future;
        return _json({
          'period_started_at': '2026-11-01T00:00:00Z',
          'tabs': tabs,
        });
      case 'GET catalog':
        final sent = r.headers['If-None-Match'];
        catalogEtagsSent.add(sent);
        if (sent == '"${catalog['etag']}"') return http.Response('', 304);
        return _json(catalog);
    }
    return _json({'detail': 'not found'}, 404);
  }

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );
}

Booking booking(
  String id, {
  int minute = 0,
  BookingStatus status = BookingStatus.queued,
}) => Booking(
  id: id,
  personId: 'p1',
  drinkId: 'd1',
  quantity: 1,
  unitPriceCents: 150,
  bookedAt: DateTime.utc(2026, 11, 2, 18).add(Duration(minutes: minute)),
  status: status,
  includedInTabs: false,
);

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late FakeServer server;
  late BookingRepositoryImpl bookings;
  late TabsRepositoryImpl tabs;
  late CatalogRepositoryImpl catalog;
  late SyncService service;

  SyncService makeService() => SyncService(
    api: BarTabApi(
      client: server.client,
      config: const ServerConfig(
        baseUrl: 'https://bar.example.test',
        deviceKey: 'test-device-key',
      ),
    ),
    bookings: bookings,
    tabs: tabs,
    catalog: catalog,
    clock: clock,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 11, 2, 19));
    server = FakeServer();
    bookings = BookingRepositoryImpl(db, clock);
    tabs = TabsRepositoryImpl(db, clock);
    catalog = CatalogRepositoryImpl(db, clock);
    service = makeService();
  });
  tearDown(() async {
    await service.dispose();
    await db.close();
  });

  Future<Map<String, String>> statuses() async => {
    for (final r in await db.select(db.bookings).get()) r.id: r.status,
  };

  Future<Set<String>> notIncluded() async =>
      (await bookings.watchNotIncluded('p1').first).map((b) => b.id).toSet();

  test('450 queued bookings are pushed as 200/200/50, all accepted', () async {
    await bookings.addAll([for (var i = 0; i < 450; i++) booking('b$i')]);

    await service.syncNow();

    expect(server.postBatches.map((b) => b.length), [200, 200, 50]);
    expect(server.postBatches.expand((b) => b).toSet().length, 450);
    expect((await statuses()).values.toSet(), {'accepted'});
    final state = await service.state.first;
    expect(state.queued, 0);
    expect(state.failed, 0);
  });

  test('mixed results map to local statuses; failures stay (RF2)', () async {
    await bookings.addAll([
      booking('a', minute: 1),
      booking('b', minute: 2),
      booking('c', minute: 3),
      booking('d', minute: 4),
    ]);
    server.resultFor.addAll({
      'a': 'accepted',
      'b': 'duplicate',
      'c': 'rejected',
      'd': 'conflict',
    });

    await service.syncNow();

    expect(await statuses(), {
      'a': 'accepted',
      'b': 'accepted',
      'c': 'rejected',
      'd': 'conflict',
    });
    final state = await service.state.first;
    expect(state.failed, 2);
    expect(state.queued, 0);
  });

  test('network failure keeps bookings queued; retry posts each id once '
      '(RF1)', () async {
    await bookings.addAll([booking('a'), booking('b'), booking('c')]);
    server.offline = true;

    await service.syncNow();

    expect((await service.state.first).isOffline, isTrue);
    expect((await service.state.first).queued, 3);
    expect((await service.state.first).lastSuccessAt, isNull);
    expect((await statuses()).values.toSet(), {'queued'});

    server.offline = false;
    clock.advance(const Duration(minutes: 1));
    await service.syncNow();

    final posted = server.postBatches.expand((b) => b).toList();
    expect(posted..sort(), ['a', 'b', 'c']);
    final state = await service.state.first;
    expect(state.isOffline, isFalse);
    expect(state.queued, 0);
    expect(state.lastSuccessAt, DateTime.utc(2026, 11, 2, 19, 1));
  });

  test(
    'tabs are saved and bookings accepted before the fetch are marked',
    () async {
      await bookings.addAll([booking('early')]);
      server.tabs = {'p1': 4200};

      await service.syncNow();

      expect(await tabs.watchTab('p1').first, 4200);
      expect(await notIncluded(), isEmpty);
    },
  );

  test(
    'a booking accepted while GET /tabs is in flight is not marked',
    () async {
      await bookings.addAll([booking('early')]);
      server.tabsGate = Completer<void>();

      final run = service.syncNow();
      await server.tabsRequested.future;
      await bookings.addAll([booking('late', status: BookingStatus.queued)]);
      await bookings.applyResults({'late': BookingStatus.accepted});
      server.tabsGate!.complete();
      await run;

      expect(await notIncluded(), {'late'});
    },
  );

  test('catalog 304 keeps the cache', () async {
    final original = catalogFromDto(CatalogDto.fromJson(catalogFixtureJson));
    await catalog.save(original);

    await service.syncNow();

    expect(server.catalogEtagsSent, ['"abc123"']);
    expect(await catalog.cached(), original);
  });

  test('catalog 200 replaces the cache', () async {
    final old = catalogFromDto(
      CatalogDto.fromJson({...catalogFixtureJson, 'etag': 'old'}),
    );
    await catalog.save(old);
    server.catalog = {
      ...catalogFixtureJson,
      'etag': 'new',
      'price_tiers': [
        {'id': 't1', 'name': 'Renamed', 'sort_order': 1},
        {'id': 't2', 'name': 'Guests', 'sort_order': 2},
      ],
    };

    await service.syncNow();

    expect(server.catalogEtagsSent, ['"old"']);
    final cached = await catalog.cached();
    expect(cached!.etag, 'new');
    expect(cached.tiers.first.name, 'Renamed');
  });

  test(
    'without a cached catalog no etag is sent and the result is saved',
    () async {
      await service.syncNow();

      expect(server.catalogEtagsSent, [null]);
      expect((await catalog.cached())!.etag, 'abc123');
    },
  );

  test('401 flags unauthorised and keeps everything; success clears it '
      '(RF5)', () async {
    await bookings.addAll([booking('a'), booking('b')]);
    await tabs.save({'p1': 999});
    server.forcedStatus = 401;

    await service.syncNow();

    var state = await service.state.first;
    expect(state.isUnauthorised, isTrue);
    expect(state.queued, 2);
    expect(state.lastSuccessAt, isNull);
    expect(await statuses(), {'a': 'queued', 'b': 'queued'});
    expect(await tabs.watchTab('p1').first, 999);
    expect(server.requests, ['POST bookings'], reason: 'run stops at 401');

    server.forcedStatus = null;
    await service.syncNow();

    state = await service.state.first;
    expect(state.isUnauthorised, isFalse);
    expect(state.queued, 0);
    expect(state.lastSuccessAt, clock.now());
  });

  test('server error is logged and leaves the state unchanged', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    await service.syncNow();
    final before = await service.state.first;

    server.forcedStatus = 500;
    clock.advance(const Duration(minutes: 1));
    await service.syncNow();

    expect(await service.state.first, before);
    expect(records.single.loggerName, 'sync');
    expect(records.single.message, contains('500'));
  });

  test('contract error is logged and does not update lastSuccessAt', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    server.catalog = {...catalogFixtureJson, 'drinks': 'not a list'};

    await service.syncNow();

    final state = await service.state.first;
    expect(state.lastSuccessAt, isNull);
    expect(state.isOffline, isFalse);
    expect(records.single.loggerName, 'sync');
  });

  test('a batch where no booking gets a result stops the push loop', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    await bookings.addAll([booking('a')]);
    server.resultIdsOverride = ['ghost'];

    await service.syncNow();

    expect(server.postBatches, [
      ['a'],
    ]);
    expect(await statuses(), {'a': 'queued'});
    expect((await service.state.first).lastSuccessAt, isNull);
    expect(records.single.loggerName, 'sync');
  });

  test('concurrent syncNow calls share one push sequence', () async {
    await bookings.addAll([booking('a'), booking('b')]);

    await Future.wait([service.syncNow(), service.syncNow()]);

    expect(server.requests, ['POST bookings', 'GET tabs', 'GET catalog']);

    await service.syncNow();
    expect(server.count('GET tabs'), 2, reason: 'a later call runs again');
  });

  test(
    'state emits the current value to each new listener and updates',
    () async {
      await bookings.addAll([booking('a')]);
      final first = await service.state.first;
      expect(first.queued, 1);
      expect(first.isOffline, isFalse);
      expect(service.state.isBroadcast, isTrue);

      final seen = <SyncState>[];
      final sub = service.state.listen(seen.add);
      addTearDown(sub.cancel);
      server.offline = true;
      await service.syncNow();
      await pumpEventQueue();

      expect(seen.last.isOffline, isTrue);
      expect(seen.last.queued, 1);
    },
  );

  test('start runs at once and every 30 s; stop cancels', () {
    fakeAsync((async) {
      final timed = makeService();
      timed.start();
      async.flushMicrotasks();
      expect(server.count('GET tabs'), 1);

      async.elapse(const Duration(seconds: 29));
      expect(server.count('GET tabs'), 1);
      async.elapse(const Duration(seconds: 1));
      expect(server.count('GET tabs'), 2);
      async.elapse(const Duration(seconds: 30));
      expect(server.count('GET tabs'), 3);

      timed.stop();
      async.elapse(const Duration(seconds: 90));
      expect(server.count('GET tabs'), 3);
    });
  });

  test('start honours an injected interval', () {
    fakeAsync((async) {
      final timed = makeService();
      timed.start(interval: const Duration(seconds: 5));
      async.elapse(const Duration(seconds: 10));
      expect(server.count('GET tabs'), 3);
      timed.stop();
    });
  });
}
