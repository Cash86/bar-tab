import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/design/chalk/chalk_extras.dart';
import 'package:bar_tab/presentation/design/coaster/coaster_extras.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/drink_selection_screen.dart';
import 'package:bar_tab/presentation/drinks/order_controller.dart';
import 'package:bar_tab/presentation/kiosk.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/names/name_tile.dart';
import 'package:bar_tab/presentation/names/screensaver.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/designs.dart';
import '../../fixtures/font_rules.dart';

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
  forEachDesign(_screensaverTests);
}

void _screensaverTests(AppDesign design) {
  late _FakeKiosk kiosk;
  final observer = RouteObserver<ModalRoute<void>>();
  final hint = find.text('Zum Buchen antippen');
  // The chalk and coaster boards draw no NameTile; names are found by text.
  final nameTile = design == AppDesign.standard
      ? find.byType(NameTile).first
      : find.text('Anton');

  Future<void> pumpScreen(WidgetTester tester) async {
    kiosk = _FakeKiosk();
    tester.view.physicalSize = design == AppDesign.standard
        ? const Size(1280, 800)
        : const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) => Future.value(_catalog)),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          kioskPlatformProvider.overrideWithValue(kiosk),
          routeObserverProvider.overrideWithValue(observer),
          designOverride(design),
          // These tests are about the screensaver, not the drink screen's own
          // 30 s idle exit.
          drinkScreenIdleTimeoutProvider.overrideWithValue(
            const Duration(hours: 1),
          ),
        ],
        child: MaterialApp(
          theme: themeFor(design),
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

  testWidgets('the hint uses the app font', (tester) async {
    await pumpScreen(tester);
    await tester.pump(kIdleTimeout);
    final text = tester.widget<Text>(hint);
    // The design's display font; Archivo in the standard design.
    expect(text.style?.fontFamily, tokensFor(design).displayFont);
    expectFontRules(tester);
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

    final tile = nameTile;
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
    await tester.tap(nameTile);
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

  testWidgets('the hint visits every position in turn', (tester) async {
    await pumpScreen(tester);
    await tester.pump(kIdleTimeout);
    for (final position in [
      ...screensaverHintPositions,
      screensaverHintPositions.first,
    ]) {
      expect(hintAlignment(tester), position);
      expect(hint, findsOneWidget);
      await tester.pump(kScreensaverHintInterval);
    }
    await unmount(tester);
  });

  if (design == AppDesign.kreidetafel) {
    testWidgets('a chalk beer glass beside the hint on a near-black board', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.pump(kIdleTimeout);
      expect(
        find.descendant(
          of: find.byKey(const Key('screensaver-hint')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ChalkBeerGlassPainter,
          ),
        ),
        findsOneWidget,
      );
      await unmount(tester);
    });
  }

  if (design == AppDesign.bierdeckel) {
    testWidgets('one coaster carries the hint and turns as it moves', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.pump(kIdleTimeout);
      final coaster = find.descendant(
        of: find.byKey(const Key('screensaver-hint')),
        matching: find.byType(SaverCoaster),
      );
      expect(coaster, findsOneWidget);
      expect(find.descendant(of: coaster, matching: hint), findsOneWidget);
      double angle() => tester.widget<SaverCoaster>(coaster).turns;
      final first = angle();
      await tester.pump(kScreensaverHintInterval);
      expect(angle(), isNot(first));
      await unmount(tester);
    });
  }
}
