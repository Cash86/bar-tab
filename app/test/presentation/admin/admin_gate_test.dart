import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/admin_bookings_screen.dart';
import 'package:bar_tab/presentation/admin/admin_session.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/kiosk.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../fixtures/designs.dart';
import '../../fixtures/fakes.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _idle = Duration(seconds: 10);

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

void main() {
  late FakeApiServer server;
  late FixedClock clock;

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 12));
    // Correct PIN is 1234; every other admin call succeeds.
    server.respond = (r) async {
      if (r.method == 'POST' && r.url.path.endsWith('admin/session')) {
        final pin = (jsonDecode(await _body(r)) as Map)['pin'];
        if (pin == '1234') return _json({'token': 't1', 'expires_in': 300});
        return _json({'detail': 'wrong_pin'}, 401);
      }
      return _json({});
    };
  });

  List<String> calls() => [
    for (final r in server.requests) '${r.method} ${r.url.path}',
  ];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(pairedStore()),
          httpClientProvider.overrideWithValue(server.client),
          clockProvider.overrideWithValue(clock),
          idleTimeoutProvider.overrideWithValue(_idle),
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

  Future<void> openGate(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('admin-gear')));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
  }

  Future<void> login(WidgetTester tester, [String pin = '1234']) async {
    await enter(tester, pin);
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
  }

  Future<void> loggedIn(WidgetTester tester) async {
    await pump(tester);
    await openGate(tester);
    await login(tester);
    expect(find.byKey(const Key('admin-tile-bookings')), findsOneWidget);
    server.requests.clear();
  }

  bool loginEnabled(WidgetTester tester) => tester
      .widget<FilledButton>(find.byKey(const Key('admin-pin-login')))
      .enabled;

  testWidgets('the gear opens the PIN prompt', (tester) async {
    await pump(tester);
    await openGate(tester);
    expect(find.text('Admin-PIN'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
    expect(loginEnabled(tester), isFalse);
  });

  testWidgets('digits are masked, login needs 4, more than 8 are ignored', (
    tester,
  ) async {
    await pump(tester);
    await openGate(tester);
    await enter(tester, '123');
    expect(find.text('•••'), findsOneWidget);
    expect(find.text('123'), findsNothing);
    expect(loginEnabled(tester), isFalse);
    await enter(tester, '4');
    expect(loginEnabled(tester), isTrue);
    await enter(tester, '567890');
    expect(find.text('••••••••'), findsOneWidget);
    await tester.tap(find.byKey(const Key('keypad-backspace')));
    await tester.pump();
    expect(find.text('•••••••'), findsOneWidget);
  });

  testWidgets('the correct PIN shows the admin home', (tester) async {
    await pump(tester);
    await openGate(tester);
    await login(tester);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Buchungen'), findsOneWidget);
    expect(find.text('Abmelden'), findsOneWidget);
    expect(find.text('Admin-PIN'), findsNothing);
  });

  testWidgets('a wrong PIN says so and clears the input', (tester) async {
    await pump(tester);
    await openGate(tester);
    await login(tester, '9999');
    expect(find.text('PIN falsch'), findsOneWidget);
    expect(find.text('••••'), findsNothing);
    expect(loginEnabled(tester), isFalse);
    expect(find.text('Admin-PIN'), findsOneWidget);
  });

  testWidgets('a lockout shows the seconds to wait', (tester) async {
    server.respond = (r) async =>
        _json({'detail': 'locked', 'retry_after': 42}, 429);
    await pump(tester);
    await openGate(tester);
    await login(tester);
    expect(find.text('Gesperrt – noch 42 s'), findsOneWidget);
    expect(find.text('Admin-PIN'), findsOneWidget);
  });

  testWidgets('offline says the server is unreachable', (tester) async {
    server.respond = (r) async => throw http.ClientException('down');
    await pump(tester);
    await openGate(tester);
    await login(tester);
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    expect(find.text('Admin-PIN'), findsOneWidget);
  });

  testWidgets('logging out returns to the name list and sends DELETE', (
    tester,
  ) async {
    await loggedIn(tester);
    await tester.tap(find.byKey(const Key('admin-logout')));
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);
    expect(calls(), ['DELETE /api/v1/admin/session']);
    expect(server.requests.single.headers['X-Admin-Token'], 't1');
  });

  testWidgets('leaving the PIN prompt during a login drops the late token', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    server.respond = (r) async {
      if (r.method == 'POST') return answer.future;
      return _json({});
    };
    await pump(tester);
    await openGate(tester);
    await enter(tester, '1234');
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);

    answer.complete(_json({'token': 't1', 'expires_in': 300}));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NameListScreen)),
    );
    expect(container.read(adminSessionProvider), isNull);
    expect(calls(), [
      'POST /api/v1/admin/session',
      'DELETE /api/v1/admin/session',
    ]);
    expect(server.requests.last.headers['X-Admin-Token'], 't1');
  });

  testWidgets('the bookings tile opens the bookings screen', (tester) async {
    await loggedIn(tester);
    server.respond = (r) async => _json(<Object>[]);
    await tester.tap(find.byKey(const Key('admin-tile-bookings')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminBookingsScreen), findsOneWidget);
  });

  testWidgets('back is blocked while logged in', (tester) async {
    await loggedIn(tester);
    expect(find.byType(BackButton), findsNothing);
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(find.byKey(const Key('admin-tile-bookings')), findsOneWidget);
  });

  testWidgets('idle on the admin home logs out and returns to the name list', (
    tester,
  ) async {
    await loggedIn(tester);
    await tester.pump(_idle);
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);
    expect(calls(), ['DELETE /api/v1/admin/session']);
  });

  testWidgets('idle on the PIN prompt returns to the name list', (
    tester,
  ) async {
    await pump(tester);
    await openGate(tester);
    await tester.pump(_idle);
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.text('Admin-PIN'), findsNothing);
  });

  testWidgets('touches keep the admin area open', (tester) async {
    await loggedIn(tester);
    for (var i = 0; i < 3; i++) {
      await tester.pump(_idle * 0.6);
      await tester.tapAt(const Offset(640, 700));
    }
    await tester.pump(_idle * 0.6);
    expect(find.byKey(const Key('admin-tile-bookings')), findsOneWidget);
    expect(calls(), isEmpty);
    await tester.pump(_idle * 0.5);
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
  });

  testWidgets('a drag in the admin area keeps the server session alive', (
    tester,
  ) async {
    await loggedIn(tester);
    // The press is too early for a ping; the move a minute later sends one.
    final gesture = await tester.startGesture(const Offset(640, 700));
    clock.advance(kAdminKeepAliveInterval);
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(calls(), ['GET /api/v1/admin/ping']);
    await gesture.up();
  });

  testWidgets('a scroll wheel in the admin area keeps the session alive', (
    tester,
  ) async {
    await loggedIn(tester);
    clock.advance(kAdminKeepAliveInterval);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(640, 700)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
    await tester.pump();
    expect(calls(), ['GET /api/v1/admin/ping']);
  });

  testWidgets('a session ended on the server shows the PIN prompt again', (
    tester,
  ) async {
    await loggedIn(tester);
    server.respond = (r) async =>
        _json({'detail': 'admin_session_required'}, 401);
    clock.advance(kAdminKeepAliveInterval);
    await tester.tapAt(const Offset(640, 700));
    await tester.pumpAndSettle();
    expect(calls(), ['GET /api/v1/admin/ping']);
    expect(find.text('Admin-PIN'), findsOneWidget);
    expect(find.byKey(const Key('admin-tile-bookings')), findsNothing);
  });

  group('design choice', () {
    late FakeConfigStore store;

    setUp(() => store = pairedStore());

    // Like BarTabApp: the theme follows the chosen design.
    Future<void> pumpDesigned(WidgetTester tester, AppDesign initial) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configStoreProvider.overrideWithValue(store),
            designOverride(initial),
            httpClientProvider.overrideWithValue(server.client),
            clockProvider.overrideWithValue(clock),
            idleTimeoutProvider.overrideWithValue(_idle),
            catalogProvider.overrideWith((ref) async => _catalog),
            rankingsProvider.overrideWith((ref) => Stream.value(null)),
            syncStateProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              theme: themeFor(ref.watch(appDesignProvider)),
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
        ),
      );
      await tester.pumpAndSettle();
      await openGate(tester);
      await login(tester);
      await tester.tap(find.byKey(const Key('admin-tile-design')));
      await tester.pumpAndSettle();
    }

    Future<void> logoutFromDesign(WidgetTester tester) async {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-logout')));
      await tester.pumpAndSettle();
    }

    Set<AppDesign> selected(WidgetTester tester) => tester
        .widget<SegmentedButton<AppDesign>>(
          find.byType(SegmentedButton<AppDesign>),
        )
        .selected;

    Color nameListBackground(WidgetTester tester) => Theme.of(
      tester.element(find.text('Wer trinkt?')),
    ).scaffoldBackgroundColor;

    testWidgets('the design screen offers the three designs', (tester) async {
      await pumpDesigned(tester, AppDesign.standard);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Design')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('design-standard')), findsOneWidget);
      expect(find.byKey(const Key('design-kreidetafel')), findsOneWidget);
      expect(find.byKey(const Key('design-bierdeckel')), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Kreidetafel'), findsOneWidget);
      expect(find.text('Bierdeckel'), findsOneWidget);
    });

    forEachDesign((design) {
      testWidgets('the current design is marked', (tester) async {
        await pumpDesigned(tester, design);
        expect(selected(tester), {design});
      });
    });

    testWidgets('choosing a design stores it and restyles the name list', (
      tester,
    ) async {
      await pumpDesigned(tester, AppDesign.standard);
      await tester.tap(find.byKey(const Key('design-kreidetafel')));
      await tester.pumpAndSettle();
      expect(store.values[kDesignConfigKey], 'kreidetafel');
      expect(selected(tester), {AppDesign.kreidetafel});

      await logoutFromDesign(tester);
      expect(
        nameListBackground(tester),
        tokensFor(AppDesign.kreidetafel).background,
      );
      expect(
        nameListBackground(tester),
        isNot(tokensFor(AppDesign.standard).background),
      );
    });

    testWidgets('a failed write keeps the old design', (tester) async {
      await pumpDesigned(tester, AppDesign.standard);
      store.writeError = StateError('disk full');
      await tester.tap(find.byKey(const Key('design-bierdeckel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(selected(tester), {AppDesign.standard});
      expect(store.values[kDesignConfigKey], isNull);
    });

    testWidgets('the chosen design survives a restart', (tester) async {
      await pumpDesigned(tester, AppDesign.standard);
      await tester.tap(find.byKey(const Key('design-bierdeckel')));
      await tester.pumpAndSettle();
      await logoutFromDesign(tester);

      // A new app start reads the design before building the scope.
      await tester.pumpWidget(const SizedBox());
      await pumpDesigned(tester, await loadDesign(store));
      expect(selected(tester), {AppDesign.bierdeckel});
      await logoutFromDesign(tester);
      expect(
        nameListBackground(tester),
        tokensFor(AppDesign.bierdeckel).background,
      );
    });
  });
}

Future<String> _body(http.BaseRequest r) async =>
    r is http.Request ? r.body : '';
