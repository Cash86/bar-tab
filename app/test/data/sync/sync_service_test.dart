import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bar_tab/data/api/api_client.dart';
import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/data/api/mappers.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/booking_repository_impl.dart';
import 'package:bar_tab/data/repositories/catalog_repository_impl.dart';
import 'package:bar_tab/data/repositories/rankings_repository_impl.dart';
import 'package:bar_tab/data/repositories/tabs_repository_impl.dart';
import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/rankings.dart';
import 'package:bar_tab/domain/repositories.dart';
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

  /// When set, POST /bookings only answers the posted ids contained here.
  Set<String>? answerOnly;

  /// Throw a SocketException for every request.
  bool offline = false;

  /// Answer every request with this status and an error body.
  int? forcedStatus;

  Map<String, int> tabs = {'p1': 1234};
  Map<String, dynamic> catalog = catalogFixtureJson;
  Map<String, dynamic> rankings = {
    'overall': {'d1': 2},
    'persons': {
      'p1': {'d1': 2},
    },
  };

  /// Answer GET /rankings with this status and an error body.
  int? rankingsStatus;

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
        final resultIds =
            resultIdsOverride ??
            [
              for (final id in ids)
                if (answerOnly?.contains(id) ?? true) id,
            ];
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
      case 'GET rankings':
        final status = rankingsStatus;
        if (status != null) return _json({'detail': 'nope'}, status);
        return _json(rankings);
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

/// Real repository whose [markIncludedInTabs] can be made to fail.
class FlakyBookings implements BookingRepository {
  FlakyBookings(this._inner);
  final BookingRepository _inner;
  bool failMark = false;

  @override
  Future<void> addAll(List<Booking> bookings) => _inner.addAll(bookings);
  @override
  Future<List<Booking>> queued({int limit = 100}) =>
      _inner.queued(limit: limit);
  @override
  Future<bool> undoHeld(Set<String> ids) => _inner.undoHeld(ids);
  @override
  Future<void> releaseHolds() => _inner.releaseHolds();
  @override
  Future<void> applyResults(Map<String, BookingStatus> results) =>
      _inner.applyResults(results);
  @override
  Future<void> markIncludedInTabs(Set<String> ids) async {
    await _inner.markIncludedInTabs(ids);
    if (failMark) throw StateError('disk full');
  }

  @override
  Future<Set<String>> acceptedNotIncludedIds() =>
      _inner.acceptedNotIncludedIds();
  @override
  Stream<List<Booking>> watchNotIncluded(String personId) =>
      _inner.watchNotIncluded(personId);
  @override
  Stream<SyncCounts> watchCounts() => _inner.watchCounts();
}

Booking booking(
  String id, {
  int minute = 0,
  BookingStatus status = BookingStatus.queued,
  DateTime? holdUntil,
}) => Booking(
  id: id,
  personId: 'p1',
  drinkId: 'd1',
  quantity: 1,
  unitPriceCents: 150,
  bookedAt: DateTime.utc(2026, 11, 2, 18).add(Duration(minutes: minute)),
  status: status,
  includedInTabs: false,
  holdUntil: holdUntil,
);

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late FakeServer server;
  late FlakyBookings bookings;
  late TabsRepositoryImpl tabs;
  late CatalogRepositoryImpl catalog;
  late RankingsRepositoryImpl rankings;
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
    rankings: rankings,
    clock: clock,
    transaction: db.transaction,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 11, 2, 19));
    server = FakeServer();
    bookings = FlakyBookings(BookingRepositoryImpl(db, clock));
    tabs = TabsRepositoryImpl(db, clock);
    catalog = CatalogRepositoryImpl(db, clock);
    rankings = RankingsRepositoryImpl(db, clock);
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

  test('a sync saves the server rankings', () async {
    await service.syncNow();

    expect(
      await rankings.watch().first,
      const DrinkRankings(
        overall: {'d1': 2},
        persons: {
          'p1': {'d1': 2},
        },
      ),
    );
  });

  test(
    'a failing rankings fetch keeps pushed bookings, tabs and catalog',
    () async {
      await bookings.addAll([booking('a')]);
      server.rankingsStatus = 404;

      await service.syncNow();

      expect(await statuses(), {'a': 'accepted'});
      expect(await tabs.watchTab('p1').first, 1234);
      expect(await catalog.cached(), isNotNull);
      expect(await rankings.watch().first, isNull);
      final state = await service.state.first;
      expect(state.isUnauthorised, isFalse);
      expect(state.lastSuccessAt, clock.now());
    },
  );

  test(
    'an invalid rankings body keeps the last rankings and still succeeds',
    () async {
      const before = DrinkRankings(overall: {'d9': 1}, persons: {});
      await rankings.save(before);
      server.rankings = {'overall': 'x'};

      await service.syncNow();

      expect(await rankings.watch().first, before);
      final state = await service.state.first;
      expect(state.isOffline, isFalse);
      expect(state.lastSuccessAt, clock.now());
    },
  );

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

  test('isSyncing is true exactly while a sync runs', () async {
    expect(service.isSyncing, isFalse);
    server.tabsGate = Completer<void>();
    final run = service.syncNow();
    await server.tabsRequested.future;
    expect(service.isSyncing, isTrue);
    server.tabsGate!.complete();
    await run;
    expect(service.isSyncing, isFalse);
  });

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

  test(
    'a partial result terminates; unanswered ids go out next pass',
    () async {
      await bookings.addAll([booking('a'), booking('b'), booking('c')]);
      server.answerOnly = {'a', 'b'};

      await service.syncNow();

      // c got no answer: the retry batch [c] makes no progress and stops.
      expect(server.postBatches, [
        ['a', 'b', 'c'],
        ['c'],
      ]);
      expect(await statuses(), {
        'a': 'accepted',
        'b': 'accepted',
        'c': 'queued',
      });

      server.answerOnly = null;
      await service.syncNow();

      expect(server.postBatches.last, ['c']);
      expect(await statuses(), {
        'a': 'accepted',
        'b': 'accepted',
        'c': 'accepted',
      });
    },
  );

  test('concurrent syncNow calls share one push sequence', () async {
    await bookings.addAll([booking('a'), booking('b')]);

    await Future.wait([service.syncNow(), service.syncNow()]);

    expect(server.requests, [
      'POST bookings',
      'GET tabs',
      'GET catalog',
      'GET rankings',
    ]);

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
      timed.dispose();
      async.flushMicrotasks();
    });
  });

  test('start honours an injected interval', () {
    fakeAsync((async) {
      final timed = makeService();
      timed.start(interval: const Duration(seconds: 5));
      async.elapse(const Duration(seconds: 10));
      expect(server.count('GET tabs'), 3);
      timed.stop();
      timed.dispose();
      async.flushMicrotasks();
    });
  });

  test('401 after an offline run clears isOffline', () async {
    server.offline = true;
    await service.syncNow();
    expect((await service.state.first).isOffline, isTrue);

    server.offline = false;
    server.forcedStatus = 401;
    await service.syncNow();

    final state = await service.state.first;
    expect(state.isOffline, isFalse);
    expect(state.isUnauthorised, isTrue);
  });

  test(
    'server and contract errors after an offline run clear isOffline',
    () async {
      final sub = Logger.root.onRecord.listen((_) {});
      addTearDown(sub.cancel);
      for (final fail in <void Function()>[
        () => server.forcedStatus = 500,
        () => server.catalog = {...catalogFixtureJson, 'drinks': 'x'},
      ]) {
        server.offline = true;
        await service.syncNow();
        expect((await service.state.first).isOffline, isTrue);

        server.offline = false;
        fail();
        await service.syncNow();
        expect((await service.state.first).isOffline, isFalse);
        server.forcedStatus = null;
      }
    },
  );

  test('a network error keeps isUnauthorised', () async {
    server.forcedStatus = 401;
    await service.syncNow();
    server.forcedStatus = null;
    server.offline = true;
    await service.syncNow();

    final state = await service.state.first;
    expect(state.isUnauthorised, isTrue);
    expect(state.isOffline, isTrue);
  });

  test('if marking included fails, the tabs are not saved either', () async {
    await tabs.save({'p1': 100});
    await bookings.addAll([booking('a')]);
    server.tabs = {'p1': 250};
    bookings.failMark = true;

    await expectLater(service.syncNow(), throwsStateError);

    expect(await tabs.watchTab('p1').first, 100);
    expect(await notIncluded(), {'a'});
    expect((await statuses())['a'], 'accepted', reason: 'push committed');

    bookings.failMark = false;
    await service.syncNow();
    expect(await tabs.watchTab('p1').first, 250);
    expect(await notIncluded(), isEmpty);
  });

  test('dispose logs an in-flight run failure instead of rethrowing', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    await bookings.addAll([booking('a')]);
    bookings.failMark = true;
    server.tabsGate = Completer<void>();

    final run = service.syncNow();
    final runFailed = expectLater(run, throwsStateError);
    await server.tabsRequested.future;
    final disposed = service.dispose();
    server.tabsGate!.complete();

    await disposed;
    await runFailed;
    expect(records.single.loggerName, 'sync');
    expect(records.single.level, Level.SEVERE);
  });

  test(
    'dispose waits for an in-flight run that ends in a network error',
    () async {
      server.tabsGate = Completer<void>();
      final run = service.syncNow();
      await server.tabsRequested.future;
      final disposed = service.dispose();
      server.offline = true;
      server.tabsGate!.complete();

      await disposed;
      await run;
    },
  );

  test('syncNow after dispose does nothing and does not throw', () async {
    await bookings.addAll([booking('a')]);
    await service.dispose();

    await service.syncNow();
    service.start();
    service.stop();

    expect(server.requests, isEmpty);
    await service.dispose();
  });

  test('held bookings are not posted before the hold expires', () async {
    final heldUntil = clock.now().add(kUndoWindow);
    await bookings.addAll([
      booking('free', minute: 1),
      booking('held', minute: 2).copyWith(holdUntil: heldUntil),
    ]);

    clock.advance(const Duration(seconds: 10));
    await service.syncNow();
    expect(server.postBatches, [
      ['free'],
    ]);
    expect(await statuses(), {'free': 'accepted', 'held': 'queued'});
    // Still counted locally while held.
    expect(await notIncluded(), {'held'});

    clock.advance(const Duration(seconds: 6)); // 16 s after the booking
    await service.syncNow();
    expect(server.postBatches, [
      ['free'],
      ['held'],
    ]);
    expect(await statuses(), {'free': 'accepted', 'held': 'accepted'});
  });

  test(
    'held bookings are not reported as waiting until the hold ends',
    () async {
      server.offline = true;
      final soon = clock.now().add(const Duration(milliseconds: 200));
      await bookings.addAll([booking('held').copyWith(holdUntil: soon)]);
      final seen = <SyncState>[];
      final sub = service.state.listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.last.queued, 0);

      clock.advance(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await service.syncNow();
      await pumpEventQueue();
      expect(seen.last.queued, 1);
      expect(seen.last.isOffline, isTrue);
    },
  );

  group('flushForSettlement', () {
    test('pushes held bookings too and reports nothing pending', () async {
      await bookings.addAll([
        booking('free', minute: 1),
        booking('held', minute: 2, holdUntil: clock.now().add(kUndoWindow)),
      ]);

      final result = await service.flushForSettlement();

      expect(
        server.postBatches.expand((b) => b),
        containsAll(['free', 'held']),
      );
      expect(result, const FlushResult(reachable: true, pending: 0, failed: 0));
    });

    test('offline: not reachable, bookings stay pending', () async {
      await bookings.addAll([
        booking('a', minute: 1),
        booking('held', minute: 2, holdUntil: clock.now().add(kUndoWindow)),
      ]);
      server.offline = true;

      final result = await service.flushForSettlement();

      expect(
        result,
        const FlushResult(reachable: false, pending: 2, failed: 0),
      );
    });

    test('unauthorised counts as not reachable', () async {
      await bookings.addAll([booking('a')]);
      server.forcedStatus = 401;

      final result = await service.flushForSettlement();

      expect(result.reachable, isFalse);
      expect(result.pending, 1);
    });

    test('reachable reflects this run, not an earlier offline one', () async {
      await bookings.addAll([booking('a')]);
      server.offline = true;
      await service.syncNow();
      server.offline = false;

      final result = await service.flushForSettlement();

      expect(result.reachable, isTrue);
      expect(result.pending, 0);
    });

    test('rejected and conflict count as failed, not pending', () async {
      await bookings.addAll([
        booking('ok', minute: 1),
        booking('bad', minute: 2),
        booking('clash', minute: 3),
      ]);
      server.resultFor.addAll({'bad': 'rejected', 'clash': 'conflict'});

      final result = await service.flushForSettlement();

      expect(result, const FlushResult(reachable: true, pending: 0, failed: 2));
    });
  });
}
