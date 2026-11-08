import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/l10n/app_localizations_de.dart';
import 'package:bar_tab/presentation/admin/admin_session.dart';
import 'package:bar_tab/presentation/admin/master_data_save.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../fixtures/catalog_fixture.dart';
import '../../fixtures/fakes.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// The catalog the fake server delivers: version 1, plus a new person from
/// version 2 on (after the write).
Map<String, dynamic> _catalogJson(int version) => {
  ...catalogFixtureJson,
  'etag': 'v$version',
  'persons': [
    ...(catalogFixtureJson['persons']! as List),
    if (version >= 2)
      {
        'id': 'p9',
        'name': 'Lena New',
        'price_tier_id': 't1',
        'is_hidden': false,
        'is_collective': false,
        'is_active': true,
      },
  ],
};

void main() {
  late AppDatabase db;
  late FakeApiServer server;
  late ProviderContainer container;
  late WidgetRef ref;

  /// Server-side catalog version; the person write bumps it.
  var version = 1;

  /// Held back while non-null: the first catalog answer (already computed).
  Completer<void>? catalogGate;
  late Completer<void> catalogRequested;
  var writeDone = false;

  setUp(() {
    version = 1;
    writeDone = false;
    catalogGate = null;
    catalogRequested = Completer<void>();
    db = AppDatabase(NativeDatabase.memory());
    server = FakeApiServer();
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (r.method == 'POST' && path.endsWith('admin/persons')) {
        version = 2;
        writeDone = true;
        return _json((_catalogJson(2)['persons'] as List).last as Object);
      }
      if (path.endsWith('/catalog')) {
        final seen = version;
        final gate = catalogGate;
        if (gate != null) {
          catalogGate = null;
          catalogRequested.complete();
          await gate.future;
        }
        if (r.headers['If-None-Match'] == '"v$seen"') {
          return http.Response('', 304);
        }
        return _json(_catalogJson(seen));
      }
      if (path.endsWith('/tabs')) {
        return _json({
          'period_started_at': '2026-11-01T00:00:00Z',
          'tabs': <String, int>{},
        });
      }
      if (path.endsWith('/rankings')) {
        return _json({
          'overall': <String, int>{},
          'persons': <String, Object>{},
        });
      }
      return _json({});
    };
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        configStoreProvider.overrideWithValue(pairedStore()),
        httpClientProvider.overrideWithValue(server.client),
        clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 11, 5))),
        syncIntervalProvider.overrideWithValue(null),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Pumps a widget exposing a [WidgetRef], logs in and syncs once.
  Future<void> prepare(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            // Listening keeps the catalog and the sync state alive.
            r.watch(catalogProvider);
            r.watch(syncStateProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await container.read(serverConfigProvider.future);
    await tester.pump();
    await container.read(syncServiceProvider)!.syncNow();
    final login = await container
        .read(adminSessionProvider.notifier)
        .login('1234');
    expect(login.$1, AdminLoginResult.success);
    await container.read(catalogProvider.future);
    server.requests.clear();
  }

  Future<SaveResult> save() =>
      saveMasterData(ref, AppLocalizationsDe(), (api, token) async {
        await api.createPerson(
          token,
          const PersonWriteDto(
            name: 'Lena New',
            priceTierId: 't1',
            isHidden: false,
            isCollective: false,
          ),
        );
      });

  List<String> calls() => [
    for (final r in server.requests) '${r.method} ${r.url.path}',
  ];

  List<String> names() => [
    for (final p in container.read(catalogProvider).value!.persons) p.name,
  ];

  testWidgets('the request comes before the sync and the new catalog is read '
      'when it returns', (tester) async {
    await tester.runAsync(() async {
      await prepare(tester);
      expect(names(), isNot(contains('Lena New')));

      final result = await save();

      expect(result, isA<Saved>());
      final posts = calls().indexOf('POST /api/v1/admin/persons');
      final gets = calls().indexOf('GET /api/v1/catalog');
      expect(posts, isNonNegative);
      expect(gets, greaterThan(posts));
      expect(names(), contains('Lena New'));
    });
  });

  testWidgets('a sync already running when the save began does not leave a '
      'stale catalog', (tester) async {
    await tester.runAsync(() async {
      await prepare(tester);
      // An in-flight sync fetched the catalog before the write landed.
      catalogGate = Completer<void>();
      final gate = catalogGate!;
      final sync = container.read(syncServiceProvider)!;
      final running = sync.syncNow();
      await catalogRequested.future;
      expect(sync.isSyncing, isTrue);

      final saving = save();
      while (!writeDone) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      gate.complete();
      final result = await saving;
      await running;

      expect(result, isA<Saved>());
      expect(names(), contains('Lena New'));
    });
  });

  testWidgets('a rejected write is a failure and does not sync', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await prepare(tester);
      final respond = server.respond;
      server.respond = (r) async => r.url.path.endsWith('admin/persons')
          ? _json({'detail': 'name_taken'}, 409)
          : respond(r);

      final result = await save();

      expect(result, isA<SaveFailed>());
      expect((result as SaveFailed).message, 'Name ist schon vergeben');
      expect(calls(), ['POST /api/v1/admin/persons']);
    });
  });

  testWidgets('an ended session is reported as such', (tester) async {
    await tester.runAsync(() async {
      await prepare(tester);
      final respond = server.respond;
      server.respond = (r) async => r.url.path.endsWith('admin/persons')
          ? _json({'detail': 'admin_session_required'}, 401)
          : respond(r);

      final result = await save();

      expect(result, isA<SaveSessionEnded>());
      expect(calls(), ['POST /api/v1/admin/persons']);
    });
  });
}
