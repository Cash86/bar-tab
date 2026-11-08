import 'dart:convert';

import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/data/repositories/local_pin_store.dart';
import 'package:bar_tab/presentation/admin/pin_change_screen.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
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

class _NoCatalog implements CatalogRepository {
  @override
  Future<Catalog?> cached() async => null;

  @override
  Future<void> save(Catalog catalog) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  late FakeApiServer server;
  late FixedClock clock;
  late FakeConfigStore config;
  late Future<http.Response> Function(http.Request r) onPin;

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    config = pairedStore();
    onPin = (r) async => http.Response('', 204);
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (path.endsWith('admin/pin') && r is http.Request) return onPin(r);
      if (path.endsWith('/tabs')) {
        return _json({
          'period_started_at': '2026-11-01T00:00:00Z',
          'tabs': <String, int>{},
        });
      }
      if (path.endsWith('/catalog')) return catalogResponse();
      if (path.endsWith('/rankings')) {
        return _json({
          'overall': <String, int>{},
          'persons': <String, Object>{},
        });
      }
      return _json({});
    };
  });

  Future<void> typeDigits(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
  }

  Future<void> openScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(config),
          localPinStoreProvider.overrideWithValue(
            LocalPinStore(config, iterations: 2),
          ),
          httpClientProvider.overrideWithValue(server.client),
          clockProvider.overrideWithValue(clock),
          catalogProvider.overrideWith((ref) async => null),
          rankingsProvider.overrideWith((ref) => Stream.value(null)),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          syncServiceProvider.overrideWith(
            (ref) => SyncService(
              api: ref.watch(apiProvider)!,
              bookings: FakeBookingRepository(clock: clock),
              tabs: FakeTabsRepository(),
              catalog: _NoCatalog(),
              rankings: FakeRankingsRepository(),
              clock: clock,
              transaction: (action) => action(),
            ),
          ),
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
    await tester.tap(find.byKey(const Key('admin-gear')));
    await tester.pumpAndSettle();
    await typeDigits(tester, '1234');
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-tile-pin')));
    await tester.pumpAndSettle();
    expect(find.byType(PinChangeScreen), findsOneWidget);
  }

  Finder next() => find.byKey(const Key('pin-change-next'));

  /// Types [digits] and confirms the step.
  Future<void> step(WidgetTester tester, String digits) async {
    await typeDigits(tester, digits);
    await tester.tap(next());
    await tester.pumpAndSettle();
  }

  List<http.Request> pinRequests() => server.requests
      .whereType<http.Request>()
      .where((r) => r.url.path.endsWith('admin/pin'))
      .toList();

  testWidgets('starts at the current PIN with masked digits', (tester) async {
    await openScreen(tester);
    expect(find.text('Aktuelle PIN'), findsOneWidget);
    await typeDigits(tester, '12');
    expect(find.text('••'), findsOneWidget);
    expect(find.text('12'), findsNothing);
    expect(tester.widget<ButtonStyleButton>(next()).enabled, isFalse);
  });

  testWidgets('a PIN shorter than 4 digits cannot be confirmed', (
    tester,
  ) async {
    await openScreen(tester);
    await step(tester, '1234');
    expect(find.text('Neue PIN'), findsOneWidget);
    await typeDigits(tester, '123');
    expect(tester.widget<ButtonStyleButton>(next()).enabled, isFalse);
    await typeDigits(tester, '45678');
    // At most 8 digits are taken.
    expect(find.text('••••••••'), findsOneWidget);
    expect(pinRequests(), isEmpty);
  });

  testWidgets('happy path sends current and new, remembers, toasts, pops', (
    tester,
  ) async {
    await openScreen(tester);
    await step(tester, '1234');
    await step(tester, '5678');
    expect(find.text('Neue PIN wiederholen'), findsOneWidget);
    await step(tester, '5678');
    final sent = jsonDecode(pinRequests().single.body) as Map<String, dynamic>;
    expect(sent['current_pin'], '1234');
    expect(sent['new_pin'], '5678');
    expect(pinRequests().single.headers['X-Admin-Token'], 't1');
    final local = LocalPinStore(config, iterations: 2);
    expect(await local.verify('5678'), isTrue);
    expect(await local.verify('1234'), isFalse);
    expect(find.text('PIN geändert'), findsOneWidget);
    expect(find.byType(PinChangeScreen), findsNothing);
  });

  testWidgets('a mismatch sends nothing and returns to the new PIN', (
    tester,
  ) async {
    await openScreen(tester);
    await step(tester, '1234');
    await step(tester, '5678');
    await step(tester, '5679');
    expect(find.text('PINs stimmen nicht überein'), findsOneWidget);
    expect(find.text('Neue PIN'), findsOneWidget);
    expect(pinRequests(), isEmpty);
  });

  testWidgets('a wrong current PIN shows the message and restarts', (
    tester,
  ) async {
    await openScreen(tester);
    onPin = (r) async => _json({'detail': 'wrong_pin'}, 403);
    await step(tester, '1234');
    await step(tester, '5678');
    await step(tester, '5678');
    expect(find.text('PIN falsch'), findsOneWidget);
    expect(find.text('Aktuelle PIN'), findsOneWidget);
    expect(find.byType(PinChangeScreen), findsOneWidget);
    expect(await LocalPinStore(config, iterations: 2).verify('5678'), isFalse);
  });

  testWidgets('a lockout shows the seconds', (tester) async {
    await openScreen(tester);
    onPin = (r) async => _json({'detail': 'locked', 'retry_after': 42}, 429);
    await step(tester, '1234');
    await step(tester, '5678');
    await step(tester, '5678');
    expect(find.text('Gesperrt – noch 42 s'), findsOneWidget);
    expect(find.text('Aktuelle PIN'), findsOneWidget);
  });

  testWidgets('unreachable shows the message and keeps the entry', (
    tester,
  ) async {
    await openScreen(tester);
    onPin = (r) async => throw http.ClientException('down');
    await step(tester, '1234');
    await step(tester, '5678');
    await step(tester, '5678');
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    expect(find.byType(PinChangeScreen), findsOneWidget);
  });

  testWidgets('a failing local store does not undo the change', (tester) async {
    await openScreen(tester);
    config.writeError = StateError('disk full');
    await step(tester, '1234');
    await step(tester, '5678');
    await step(tester, '5678');
    expect(find.text('PIN geändert'), findsOneWidget);
    expect(find.byType(PinChangeScreen), findsNothing);
  });

  testWidgets('an ended session leaves to the PIN prompt', (tester) async {
    await openScreen(tester);
    onPin = (r) async => _json({'detail': 'admin_session_required'}, 401);
    await step(tester, '1234');
    await step(tester, '5678');
    await step(tester, '5678');
    expect(find.byType(PinChangeScreen), findsNothing);
    expect(find.byKey(const Key('admin-pin-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
