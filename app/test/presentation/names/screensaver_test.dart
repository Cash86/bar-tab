import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/drinks/drink_selection_screen.dart';
import 'package:bar_tab/presentation/kiosk.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/names/name_tile.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeKiosk implements KioskPlatform {
  final calls = <String>[];

  @override
  Future<void> setLandscape() async {}
  @override
  Future<void> setImmersive() async {}
  @override
  Future<void> keepScreenOn() async {}
  @override
  Future<void> dim() async => calls.add('dim');
  @override
  Future<void> undim() async => calls.add('undim');
}

const _catalog = Catalog(
  tiers: [PriceTier(id: 't1', name: 'Members', sortOrder: 1)],
  persons: [
    Person(
      id: 'a',
      name: 'Anton',
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
  late _FakeKiosk kiosk;
  final observer = RouteObserver<ModalRoute<void>>();
  final hint = find.text('Zum Buchen antippen');

  Future<void> pumpScreen(WidgetTester tester) async {
    kiosk = _FakeKiosk();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) => Future.value(_catalog)),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          kioskPlatformProvider.overrideWithValue(kiosk),
          routeObserverProvider.overrideWithValue(observer),
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
          navigatorObservers: [observer],
          home: const NameListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  Alignment hintAlignment(WidgetTester tester) =>
      tester.widget<Align>(find.byKey(const Key('screensaver-hint'))).alignment
          as Alignment;

  testWidgets('no overlay before the idle timeout, overlay and dim after', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.pump(kIdleTimeout - const Duration(seconds: 1));
    expect(hint, findsNothing);
    expect(kiosk.calls, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(hint, findsOneWidget);
    expect(kiosk.calls, ['dim']);
    await unmount(tester);
  });

  testWidgets('a pointer event at 1:59 restarts the timer', (tester) async {
    await pumpScreen(tester);
    await tester.pump(const Duration(minutes: 1, seconds: 59));
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(seconds: 2));
    expect(hint, findsNothing);
    await tester.pump(kIdleTimeout);
    expect(hint, findsOneWidget);
    await unmount(tester);
  });

  testWidgets('first tap only wakes; second tap works normally', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.pump(kIdleTimeout);
    expect(hint, findsOneWidget);

    final tile = find.byType(NameTile).first;
    final center = tester.getCenter(tile);
    await tester.tapAt(center);
    await tester.pump();
    expect(hint, findsNothing);
    expect(kiosk.calls, ['dim', 'undim']);
    expect(find.byType(DrinkSelectionScreen), findsNothing);

    // The idle timer restarted: nothing at 1:59.
    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(hint, findsNothing);

    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DrinkSelectionScreen), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('hint moves every 20 seconds', (tester) async {
    await pumpScreen(tester);
    await tester.pump(kIdleTimeout);
    final first = hintAlignment(tester);
    await tester.pump(const Duration(seconds: 19));
    expect(hintAlignment(tester), first);
    await tester.pump(const Duration(seconds: 1));
    expect(hintAlignment(tester), isNot(first));
    await unmount(tester);
  });

  testWidgets('disposing while dimmed restores brightness, no timers left', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.pump(kIdleTimeout);
    await unmount(tester);
    expect(kiosk.calls, ['dim', 'undim']);
    // Test framework fails on pending timers after this point.
  });

  Future<void> openDrinkScreen(WidgetTester tester) async {
    await tester.tap(find.byType(NameTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DrinkSelectionScreen), findsOneWidget);
  }

  testWidgets('returning from the drink screen re-arms a full timeout', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openDrinkScreen(tester);
    await tester.pump(const Duration(minutes: 1, seconds: 50));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(minutes: 1, seconds: 55));
    expect(hint, findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(hint, findsOneWidget);
    await unmount(tester);
  });

  testWidgets('screensaver never shows over the drink screen', (tester) async {
    await pumpScreen(tester);
    await openDrinkScreen(tester);
    await tester.pump(const Duration(minutes: 3));
    expect(hint, findsNothing);
    expect(kiosk.calls, isEmpty);
    await unmount(tester);
  });

  testWidgets('app resume wakes the screensaver and re-arms the timer', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.pump(kIdleTimeout);
    expect(hint, findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(hint, findsNothing);
    expect(kiosk.calls, ['dim', 'undim']);
    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(hint, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(hint, findsOneWidget);
    await unmount(tester);
  });
}
