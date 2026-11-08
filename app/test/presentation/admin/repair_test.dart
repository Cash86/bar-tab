import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/local_pin_store.dart';
import 'package:bar_tab/data/repositories/server_config_repository_impl.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/admin_session.dart';
import 'package:bar_tab/presentation/admin/repair_screen.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../fixtures/fakes.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _catalog = Catalog(
  tiers: [PriceTier(id: 't1', name: 'Members', sortOrder: 1)],
  persons: [
    Person(
      id: 'p1',
      name: 'Kim Example',
      priceTierId: 't1',
      isHidden: false,
      isCollective: false,
      isActive: true,
    ),
  ],
  groups: [],
  drinks: [],
  etag: 'e',
);

const _warning =
    'Das Tablet wird mit einem anderen Server verbunden. '
    'Wartende Buchungen bleiben erhalten.';

/// How the paired (old) server answers an admin login.
enum _Old { up, down, keyRejected }

void main() {
  late FakeApiServer server;
  late FixedClock clock;
  late FakeConfigStore store;
  late AppDatabase db;
  late _Old old;
  late int tokens;

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 8, 20));
    store = pairedStore();
    db = AppDatabase(NativeDatabase.memory());
    old = _Old.up;
    tokens = 0;
    // The paired server is bar.example (PIN 1234); new.example is where the
    // tablet is re-paired to.
    server.respond = (r) async {
      if (r.url.host == 'new.example') return catalogResponse();
      switch (old) {
        case _Old.down:
          throw http.ClientException('down');
        case _Old.keyRejected:
          return _json({'detail': 'unauthorised'}, 401);
        case _Old.up:
          break;
      }
      if (r.method == 'POST' && r.url.path.endsWith('admin/session')) {
        final pin = (jsonDecode((r as http.Request).body) as Map)['pin'];
        if (pin != '1234') return _json({'detail': 'wrong_pin'}, 401);
        tokens++;
        return _json({'token': 'token-$tokens', 'expires_in': 300});
      }
      return _json({});
    };
  });

  tearDown(() => db.close());

  List<String> calls() => [
    for (final r in server.requests)
      '${r.method} ${r.url.host}${r.url.path}'
          '${r.headers['X-Admin-Token'] == null ? '' : ' ${r.headers['X-Admin-Token']}'}',
  ];

  Future<void> rememberLocalPin(WidgetTester tester, String pin) =>
      tester.runAsync(() => LocalPinStore(store, iterations: 2).remember(pin));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          configStoreProvider.overrideWithValue(store),
          localPinStoreProvider.overrideWith(
            (ref) =>
                LocalPinStore(ref.watch(configStoreProvider), iterations: 2),
          ),
          httpClientProvider.overrideWithValue(server.client),
          clockProvider.overrideWithValue(clock),
          syncIntervalProvider.overrideWithValue(null),
          catalogProvider.overrideWith((ref) async => _catalog),
          rankingsProvider.overrideWith((ref) => Stream.value(null)),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: BarTabTheme.data,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const NameListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(NameListScreen, skipOffstage: false)),
  );

  Future<void> openGate(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('admin-gear')));
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester, [String pin = '1234']) async {
    for (final d in pin.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
  }

  Finder repairOnlyHome() => find.text('Admin (offline)');

  Future<void> offlineUnlocked(WidgetTester tester) async {
    old = _Old.down;
    await rememberLocalPin(tester, '1234');
    await pump(tester);
    await openGate(tester);
    await login(tester);
    expect(repairOnlyHome(), findsOneWidget);
  }

  group('offline fallback', () {
    testWidgets('unreachable server, local hash and right PIN open the '
        'repair-only home', (tester) async {
      await offlineUnlocked(tester);
      expect(find.byKey(const Key('admin-repair')), findsOneWidget);
      expect(find.byKey(const Key('admin-logout')), findsOneWidget);
      expect(find.byKey(const Key('admin-tile-bookings')), findsNothing);
      expect(container(tester).read(localAdminProvider), isTrue);
      expect(container(tester).read(adminSessionProvider), isNull);
    });

    testWidgets('a wrong local PIN says so', (tester) async {
      old = _Old.down;
      await rememberLocalPin(tester, '1234');
      await pump(tester);
      await openGate(tester);
      await login(tester, '9999');
      expect(find.text('PIN falsch'), findsOneWidget);
      expect(find.text('Admin-PIN'), findsOneWidget);
      expect(repairOnlyHome(), findsNothing);
    });

    testWidgets('without a local hash the server is unreachable', (
      tester,
    ) async {
      old = _Old.down;
      await pump(tester);
      await openGate(tester);
      await login(tester);
      expect(find.text('Server nicht erreichbar'), findsOneWidget);
      expect(repairOnlyHome(), findsNothing);
    });

    testWidgets('a rejected device key behaves like unreachable', (
      tester,
    ) async {
      old = _Old.keyRejected;
      await rememberLocalPin(tester, '1234');
      await pump(tester);
      await openGate(tester);
      await login(tester);
      expect(repairOnlyHome(), findsOneWidget);
    });

    testWidgets('a wrong PIN on a reachable server never falls back', (
      tester,
    ) async {
      // The local hash still holds an old PIN the server no longer accepts.
      await rememberLocalPin(tester, '5555');
      await pump(tester);
      await openGate(tester);
      await login(tester, '5555');
      expect(find.text('PIN falsch'), findsOneWidget);
      expect(repairOnlyHome(), findsNothing);
    });

    testWidgets('a server lockout never falls back', (tester) async {
      await rememberLocalPin(tester, '1234');
      server.respond = (r) async =>
          _json({'detail': 'locked', 'retry_after': 42}, 429);
      await pump(tester);
      await openGate(tester);
      await login(tester);
      expect(find.text('Gesperrt – noch 42 s'), findsOneWidget);
      expect(repairOnlyHome(), findsNothing);
    });

    testWidgets('5 wrong local PINs lock for 60 s', (tester) async {
      old = _Old.down;
      await rememberLocalPin(tester, '1234');
      await pump(tester);
      await openGate(tester);
      for (var i = 0; i < 5; i++) {
        await login(tester, '9999');
        expect(find.text('PIN falsch'), findsOneWidget);
      }
      await login(tester);
      expect(find.text('Gesperrt – noch 60 s'), findsOneWidget);
      expect(repairOnlyHome(), findsNothing);

      clock.advance(const Duration(seconds: 45));
      await login(tester);
      expect(find.text('Gesperrt – noch 15 s'), findsOneWidget);

      // Leaving and re-entering the gate does not lift the lock.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await openGate(tester);
      await login(tester);
      expect(find.text('Gesperrt – noch 15 s'), findsOneWidget);

      clock.advance(const Duration(seconds: 15));
      await login(tester);
      expect(repairOnlyHome(), findsOneWidget);
    });

    testWidgets('idle 2 min in the repair-only home returns to the name '
        'list and locks', (tester) async {
      await offlineUnlocked(tester);
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(find.text('Wer trinkt?'), findsOneWidget);
      expect(repairOnlyHome(), findsNothing);
      expect(container(tester).read(localAdminProvider), isFalse);

      await openGate(tester);
      expect(find.text('Admin-PIN'), findsOneWidget);
    });

    testWidgets('logging out of the repair-only home locks', (tester) async {
      await offlineUnlocked(tester);
      await tester.tap(find.byKey(const Key('admin-logout')));
      await tester.pumpAndSettle();
      expect(find.text('Wer trinkt?'), findsOneWidget);
      expect(container(tester).read(localAdminProvider), isFalse);
    });

    testWidgets('back is blocked in the repair-only home', (tester) async {
      await offlineUnlocked(tester);
      expect(find.byType(BackButton), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(repairOnlyHome(), findsOneWidget);
    });

    testWidgets('leaving the prompt during an offline login unlocks nothing', (
      tester,
    ) async {
      await rememberLocalPin(tester, '1234');
      final answer = Completer<http.Response>();
      server.respond = (r) => answer.future;
      await pump(tester);
      await openGate(tester);
      for (final d in '1234'.split('')) {
        await tester.tap(find.byKey(Key('keypad-$d')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('admin-pin-login')));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      answer.completeError(http.ClientException('down'));
      await tester.pumpAndSettle();
      expect(container(tester).read(localAdminProvider), isFalse);
      await openGate(tester);
      expect(find.text('Admin-PIN'), findsOneWidget);
    });
  });

  group('repair flow', () {
    Future<void> openWarning(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('admin-repair')));
      await tester.pumpAndSettle();
    }

    testWidgets('offline: the link shows the warning, cancel stays', (
      tester,
    ) async {
      await offlineUnlocked(tester);
      await openWarning(tester);
      expect(find.text(_warning), findsOneWidget);
      expect(find.text('Weiter'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text(_warning), findsNothing);
      expect(repairOnlyHome(), findsOneWidget);
      expect(find.byType(RepairScreen), findsNothing);
    });

    testWidgets('offline: the form is pre-filled with the current pairing', (
      tester,
    ) async {
      await offlineUnlocked(tester);
      await openWarning(tester);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.byType(RepairScreen), findsOneWidget);
      final url = tester.widget<TextField>(find.byKey(const Key('setup-url')));
      final key = tester.widget<TextField>(find.byKey(const Key('setup-key')));
      expect(url.controller!.text, 'https://bar.example');
      expect(key.controller!.text, 'key-a');
      expect(key.obscureText, isTrue);
    });

    Future<void> submitNew(
      WidgetTester tester, {
      String url = 'https://new.example',
      String key = 'key-b',
    }) async {
      await tester.enterText(find.byKey(const Key('setup-url')), url);
      await tester.enterText(find.byKey(const Key('setup-key')), key);
      await tester.tap(find.text('Verbinden'));
      await tester.pumpAndSettle();
    }

    testWidgets('offline: a successful re-pair stores the new pairing, '
        'locks and returns to the name list', (tester) async {
      await offlineUnlocked(tester);
      await openWarning(tester);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await submitNew(tester);

      expect(find.text('Wer trinkt?'), findsOneWidget);
      expect(find.byType(RepairScreen), findsNothing);
      expect(
        store.values[ServerConfigRepositoryImpl.baseUrlKey],
        'https://new.example',
      );
      expect(store.values[ServerConfigRepositoryImpl.deviceKeyKey], 'key-b');
      expect(container(tester).read(localAdminProvider), isFalse);
      // The local hash belongs to the club's PIN and is kept.
      expect(store.values[LocalPinStore.key], isNotNull);
    });

    testWidgets('a failed re-pair keeps the old pairing and shows the '
        'first-start error', (tester) async {
      await offlineUnlocked(tester);
      await openWarning(tester);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await submitNew(tester, url: 'https://typo.example');

      expect(find.text('Server nicht erreichbar'), findsOneWidget);
      expect(find.byType(RepairScreen), findsOneWidget);
      expect(
        store.values[ServerConfigRepositoryImpl.baseUrlKey],
        'https://bar.example',
      );
      expect(store.values[ServerConfigRepositoryImpl.deviceKeyKey], 'key-a');

      await submitNew(tester, url: 'bar.example');
      expect(find.text('Adresse ungültig'), findsOneWidget);
    });

    testWidgets('idle on the repair form returns to the name list and locks', (
      tester,
    ) async {
      await offlineUnlocked(tester);
      await openWarning(tester);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(find.text('Wer trinkt?'), findsOneWidget);
      expect(container(tester).read(localAdminProvider), isFalse);
    });

    Future<void> onlineLoggedIn(WidgetTester tester) async {
      await pump(tester);
      await openGate(tester);
      await login(tester);
      expect(find.byKey(const Key('admin-tile-bookings')), findsOneWidget);
      server.requests.clear();
    }

    testWidgets('online: the link asks the PIN again before the warning', (
      tester,
    ) async {
      await onlineLoggedIn(tester);
      await openWarning(tester);
      expect(find.text('Admin-PIN'), findsOneWidget);
      expect(find.text(_warning), findsNothing);

      await login(tester, '9999');
      expect(find.text('PIN falsch'), findsOneWidget);
      expect(find.text(_warning), findsNothing);

      await login(tester);
      expect(find.text(_warning), findsOneWidget);
      // The fresh session replaces the old one, which is revoked.
      expect(container(tester).read(adminSessionProvider), 'token-2');
      expect(calls(), [
        'POST bar.example/api/v1/admin/session',
        'POST bar.example/api/v1/admin/session',
        'DELETE bar.example/api/v1/admin/session token-1',
      ]);
    });

    testWidgets('idle on the online PIN re-ask returns to the name list', (
      tester,
    ) async {
      await onlineLoggedIn(tester);
      await openWarning(tester);
      expect(find.text('Admin-PIN'), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(find.text('Wer trinkt?'), findsOneWidget);
      expect(find.text('Admin-PIN'), findsNothing);
      expect(container(tester).read(adminSessionProvider), isNull);
    });

    testWidgets('idle on the online warning returns to the name list', (
      tester,
    ) async {
      await onlineLoggedIn(tester);
      await openWarning(tester);
      await login(tester);
      expect(find.text(_warning), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(find.text('Wer trinkt?'), findsOneWidget);
      expect(find.text(_warning), findsNothing);
      expect(container(tester).read(adminSessionProvider), isNull);
    });

    testWidgets('idle on the offline warning returns to the name list', (
      tester,
    ) async {
      await offlineUnlocked(tester);
      await openWarning(tester);
      expect(find.text(_warning), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(find.text('Wer trinkt?'), findsOneWidget);
      expect(find.text(_warning), findsNothing);
      expect(container(tester).read(localAdminProvider), isFalse);
    });

    testWidgets('online: back from the PIN step returns to the admin home', (
      tester,
    ) async {
      await onlineLoggedIn(tester);
      await openWarning(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-tile-bookings')), findsOneWidget);
      expect(container(tester).read(adminSessionProvider), 'token-1');
    });

    testWidgets('online: a successful re-pair drops the old admin session', (
      tester,
    ) async {
      await onlineLoggedIn(tester);
      await openWarning(tester);
      await login(tester);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      server.requests.clear();
      await submitNew(tester);

      expect(find.text('Wer trinkt?'), findsOneWidget);
      expect(container(tester).read(adminSessionProvider), isNull);
      expect(
        store.values[ServerConfigRepositoryImpl.baseUrlKey],
        'https://new.example',
      );
      expect(calls(), [
        'GET new.example/api/v1/catalog',
        'DELETE bar.example/api/v1/admin/session token-2',
      ]);
    });
  });
}
