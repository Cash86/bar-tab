import 'dart:async';

import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/design/chalk/chalk_extras.dart';
import 'package:bar_tab/presentation/design/coaster/coaster_extras.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/drink_selection_screen.dart';
import 'package:bar_tab/presentation/kiosk.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/names/undo_banner.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/designs.dart';
import '../../fixtures/fakes.dart';
import '../../fixtures/font_rules.dart';

const _nbsp = '\u00A0';

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
    Person(
      id: 'p2',
      name: 'Lou Sample',
      priceTierId: 't1',
      isHidden: false,
      isCollective: false,
      isActive: true,
    ),
  ],
  groups: [DrinkGroup(id: 'g1', name: 'Soft', sortOrder: 1, color: 0xFF72B8DE)],
  drinks: [
    Drink(
      id: 'd1',
      name: 'Apfelschorle',
      groupId: 'g1',
      crateSize: 12,
      sortOrder: 1,
      isHidden: false,
      isActive: true,
      prices: {'t1': 150},
    ),
  ],
  etag: 'e',
);

class _FakeKiosk implements KioskPlatform {
  @override
  Future<void> setLandscape() async {}
  @override
  Future<void> setImmersive() async {}
  @override
  Future<void> keepScreenOn() async {}
  @override
  Future<void> dim() async {}
  @override
  Future<void> undim() async {}
}

/// Follows the test's fake time, so holds expire while the test pumps;
/// [advance] makes the clock jump on top of that.
class _FakeTimeClock implements Clock {
  Duration _offset = Duration.zero;

  @override
  DateTime now() =>
      TestWidgetsFlutterBinding.instance.clock.now().toUtc().add(_offset);

  void advance(Duration d) => _offset += d;
}

void main() {
  forEachDesign(_bannerTests);
}

void _bannerTests(AppDesign design) {
  late _FakeTimeClock clock;
  late FakeBookingRepository bookings;
  late FakeSyncService sync;
  final undo = find.text('Rückgängig');

  setUp(() {
    clock = _FakeTimeClock();
    bookings = FakeBookingRepository(clock: clock);
    sync = FakeSyncService();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    List<Override> extra = const [],
  }) async {
    tester.view.physicalSize = design == AppDesign.standard
        ? const Size(1280, 800)
        : const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final observer = RouteObserver<ModalRoute<void>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) async => _catalog),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          bookingRepositoryProvider.overrideWithValue(bookings),
          rankingsRepositoryProvider.overrideWithValue(
            FakeRankingsRepository(),
          ),
          tabsRepositoryProvider.overrideWithValue(
            FakeTabsRepository({'p1': 4435, 'p2': 0}, bookings),
          ),
          syncServiceProvider.overrideWithValue(sync),
          clockProvider.overrideWithValue(clock),
          kioskPlatformProvider.overrideWithValue(_FakeKiosk()),
          routeObserverProvider.overrideWithValue(observer),
          designOverride(design),
          ...extra,
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

  /// Opens [name], taps Apfelschorle [n] times, presses Fertig and waits
  /// until the name list is back.
  Future<void> book(WidgetTester tester, String name, [int n = 1]) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    for (var i = 0; i < n; i++) {
      await tester.tap(find.byKey(const ValueKey('drink-d1')));
      await tester.pump();
    }
    await tester.tap(find.text('Fertig'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(DrinkSelectionScreen), findsNothing);
  }

  testWidgets('banner names the order and disappears after the undo window', (
    tester,
  ) async {
    await pumpApp(tester);
    await book(tester, 'Kim Example', 2);
    expect(find.text('Kim Example: 2× Apfelschorle gebucht'), findsOneWidget);
    expect(undo, findsOneWidget);
    expect(find.byKey(const Key('undo-banner-progress')), findsOneWidget);

    // Counted from the return to the name list (the pop takes a moment).
    await tester.pump(kUndoWindow - const Duration(seconds: 1));
    expect(undo, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(undo, findsNothing);
    expect(find.textContaining('gebucht'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the banner ends exactly when the hold expires', (tester) async {
    await pumpApp(tester);
    // A slow write: the name list is back 2 s after the hold started.
    final gate = Completer<void>();
    bookings.addAllGate = gate;
    await tester.tap(find.text('Kim Example'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drink-d1')));
    await tester.pump();
    await tester.tap(find.text('Fertig'));
    await tester.pump(const Duration(seconds: 2));
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(undo, findsOneWidget);

    final until = bookings.bookings.single.holdUntil!;
    await tester.pump(
      until.difference(clock.now()) - const Duration(milliseconds: 1),
    );
    expect(undo, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(undo, findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the held bookings are synced once the undo window is over', (
    tester,
  ) async {
    await pumpApp(tester);
    await book(tester, 'Kim Example');
    final booking = bookings.bookings.single;
    expect(booking.holdUntil, booking.bookedAt.add(kUndoWindow));
    // The sync right after the commit (it pushes older bookings only).
    expect(sync.syncNowCalls, 1);
    // One second after the hold expires.
    final syncAt = booking.holdUntil!.add(const Duration(seconds: 1));
    await tester.pump(
      syncAt.difference(clock.now()) - const Duration(milliseconds: 1),
    );
    expect(sync.syncNowCalls, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(sync.syncNowCalls, 2);
  });

  testWidgets('Rückgängig inside the window removes the order', (tester) async {
    await pumpApp(tester);
    await book(tester, 'Kim Example', 2);
    final ids = {for (final b in bookings.bookings) b.id};
    await tester.pump(const Duration(seconds: 10));

    await tester.tap(undo);
    await tester.pump();
    expect(bookings.undoCalls, [ids]);
    expect(bookings.bookings, isEmpty);
    expect(find.text('Buchung zurückgenommen'), findsOneWidget);
    expect(undo, findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Buchung zurückgenommen'), findsNothing);

    // The running total is back to the server tab.
    await tester.tap(find.text('Kim Example'));
    await tester.pumpAndSettle();
    expect(find.text('44,35$_nbsp€'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30)); // idle exit
    await tester.pumpAndSettle();
  });

  testWidgets('Rückgängig after the hold expired says it is too late', (
    tester,
  ) async {
    await pumpApp(tester);
    await book(tester, 'Kim Example');
    // The clock jumps past the hold while the banner is still up.
    clock.advance(kUndoWindow);

    await tester.tap(undo);
    await tester.pump();
    expect(bookings.bookings, hasLength(1));
    expect(find.text('Zu spät – bitte beim Admin stornieren'), findsOneWidget);
    expect(undo, findsNothing);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(find.text('Zu spät – bitte beim Admin stornieren'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Zu spät – bitte beim Admin stornieren'), findsNothing);
    await tester.pump(kUndoWindow);
  });

  testWidgets('a newer order replaces the banner; only it is undone', (
    tester,
  ) async {
    await pumpApp(tester);
    await book(tester, 'Kim Example');
    final first = bookings.bookings.single;
    await book(tester, 'Lou Sample', 2);
    expect(find.text('Kim Example: 1× Apfelschorle gebucht'), findsNothing);
    expect(find.text('Lou Sample: 2× Apfelschorle gebucht'), findsOneWidget);

    await tester.tap(undo);
    await tester.pump();
    expect(bookings.bookings, [first]);
    await tester.pump(kUndoWindow + const Duration(seconds: 1));
  });

  testWidgets('the banner leaves the admin gear free', (tester) async {
    await pumpApp(tester);
    await book(tester, 'Kim Example', 2);
    final gear = find.byKey(const Key('admin-gear'));
    expect(gear.hitTestable(), findsOneWidget);
    final banner = tester.getRect(find.byType(UndoBanner));
    expect(banner.overlaps(tester.getRect(gear)), isFalse);
    await tester.pump(kUndoWindow);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the undo info leaves the admin gear free', (tester) async {
    await pumpApp(tester);
    await book(tester, 'Kim Example');
    await tester.tap(undo);
    await tester.pump();
    await tester.pump();
    final gear = find.byKey(const Key('admin-gear'));
    expect(find.byType(UndoInfo), findsOneWidget);
    expect(gear.hitTestable(), findsOneWidget);
    final info = tester.getRect(find.byType(UndoInfo));
    expect(info.overlaps(tester.getRect(gear)), isFalse);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('the screensaver waits while the banner is up', (tester) async {
    await pumpApp(
      tester,
      extra: [
        idleTimeoutProvider.overrideWithValue(const Duration(seconds: 4)),
      ],
    );
    final hint = find.text('Zum Buchen antippen');
    await book(tester, 'Kim Example');
    await tester.pump(const Duration(seconds: 12));
    expect(hint, findsNothing);
    expect(undo, findsOneWidget);
    // The tap reaches the button, it is not swallowed as a wake-up touch.
    await tester.tap(undo);
    await tester.pump();
    expect(bookings.bookings, isEmpty);

    // With nothing to undo any more the screensaver comes as usual.
    await tester.pump(const Duration(seconds: 3)); // info text ends
    await tester.pump(const Duration(seconds: 5));
    expect(hint, findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the line drains over the undo window', (tester) async {
    await pumpApp(tester);
    await book(tester, 'Kim Example');
    await tester.pump(const Duration(seconds: 1));
    // The drawn line, as painted (a design may shrink it by a transform).
    double line() => tester
        .getRect(
          find
              .descendant(
                of: find.byKey(const Key('undo-banner-progress')),
                matching: find.byType(ColoredBox),
              )
              .last,
        )
        .width;
    final start = line();
    expect(start, greaterThan(0));
    await tester.pump(const Duration(seconds: 5));
    final later = line();
    expect(later, lessThan(start));
    await tester.pump(const Duration(seconds: 5));
    expect(line(), lessThan(later));
    expectFontRules(tester);
    await tester.pump(kUndoWindow);
  });

  if (design != AppDesign.standard) {
    testWidgets('the draining line and the slide repaint on their own layer', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(design),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: UndoBanner(
              design: design,
              text: 'Kim: 1× Lager gebucht',
              secondsLeft: kUndoWindow.inSeconds,
              onUndo: () {},
            ),
          ),
        ),
      );
      expect(
        tester.renderObject(find.byType(DrainingLine)),
        isA<RenderRepaintBoundary>(),
      );
      if (design == AppDesign.bierdeckel) {
        expect(
          tester.renderObject(find.byType(SlideInFromTop)),
          isA<RenderRepaintBoundary>(),
        );
      }
      await tester.pumpAndSettle();
    });
  }

  if (design == AppDesign.kreidetafel) {
    testWidgets('the banner is a pinned paper note', (tester) async {
      await pumpApp(tester);
      await book(tester, 'Kim Example');
      final note = find.byType(ChalkNote);
      expect(note, findsOneWidget);
      expect(find.descendant(of: note, matching: undo), findsOneWidget);
      expect(
        find.descendant(
          of: note,
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ChalkPinPainter,
          ),
        ),
        findsOneWidget,
      );
      await tester.pump(kUndoWindow);
    });
  }

  if (design == AppDesign.bierdeckel) {
    testWidgets('the banner is a till receipt sliding in from the top', (
      tester,
    ) async {
      await pumpApp(tester);
      await book(tester, 'Kim Example');
      final receipt = find.byType(TillReceipt);
      expect(receipt, findsOneWidget);
      expect(find.descendant(of: receipt, matching: undo), findsOneWidget);
      final text = tester.widget<Text>(
        find.text('Kim Example: 1× Apfelschorle gebucht'),
      );
      expect(text.style?.fontFamily, 'monospace');
      // Hangs from the top edge once it is in.
      expect(tester.getRect(receipt).top, 0);
      await tester.pump(kUndoWindow);
    });

    testWidgets('the receipt moves down into place', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(design),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 28,
                  child: UndoBanner(
                    design: design,
                    text: 'Kim: 1× Lager gebucht',
                    secondsLeft: kUndoWindow.inSeconds,
                    onUndo: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final start = tester.getRect(find.byType(TillReceipt)).top;
      expect(start, lessThan(0));
      await tester.pump(const Duration(milliseconds: 150));
      final mid = tester.getRect(find.byType(TillReceipt)).top;
      expect(mid, greaterThan(start));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TillReceipt)).top, 0);
    });
  }
}
