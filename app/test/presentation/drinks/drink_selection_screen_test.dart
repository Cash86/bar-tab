import 'dart:async';

import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/rankings.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/drink_selection_screen.dart';
import 'package:bar_tab/presentation/drinks/order_bar.dart';
import 'package:bar_tab/presentation/drinks/order_controller.dart';
import 'package:bar_tab/presentation/drinks/quantity_sheet.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/designs.dart';
import '../../fixtures/fakes.dart';

const _nbsp = ' ';

Drink drink(
  String id,
  String name,
  String group,
  Map<String, int> prices, {
  int sort = 0,
  int crate = 20,
  bool hidden = false,
  bool active = true,
}) => Drink(
  id: id,
  name: name,
  groupId: group,
  crateSize: crate,
  sortOrder: sort,
  isHidden: hidden,
  isActive: active,
  prices: prices,
);

Catalog testCatalog({int lagerPrice = 115}) => Catalog(
  tiers: const [
    PriceTier(id: 't1', name: 'Members', sortOrder: 1),
    PriceTier(id: 't2', name: 'Guests', sortOrder: 2),
  ],
  persons: const [
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
      priceTierId: 't2',
      isHidden: false,
      isCollective: false,
      isActive: true,
    ),
  ],
  groups: const [
    DrinkGroup(id: 'g1', name: 'Beer', sortOrder: 1, color: 0xFFE3A33A),
    DrinkGroup(id: 'g2', name: 'Soft', sortOrder: 2, color: 0xFF72B8DE),
    DrinkGroup(id: 'g3', name: 'Secret Stash', sortOrder: 3, color: 0xFFC79BF0),
  ],
  drinks: [
    drink('d1', 'Lager', 'g1', {'t1': lagerPrice, 't2': 150}, sort: 1),
    drink('d2', 'Wheat', 'g1', {'t1': 130}, sort: 2),
    drink('d3', 'Lemonade', 'g2', {'t1': 60, 't2': 80}, sort: 1, crate: 12),
    for (var i = 0; i < 7; i++)
      drink('j$i', 'Juice $i', 'g2', {'t1': 70, 't2': 90}, sort: 2 + i),
    drink('gx', 'Guest Special', 'g2', {'t2': 300}, sort: 20),
    drink('rx', 'Retired', 'g2', {'t1': 50}, active: false),
    drink('sx', 'Hidden Gin', 'g3', {'t1': 400}, hidden: true),
  ],
  etag: 'e',
);

void main() {
  late FakeBookingRepository bookings;
  late FakeSyncService sync;
  late Catalog catalog;
  final delay = kAutoBookDelay.inSeconds;

  setUp(() {
    bookings = FakeBookingRepository();
    sync = FakeSyncService();
    catalog = testCatalog();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    List<Override> extra = const [],
    DrinkRankings? rankings,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) async => catalog),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          bookingRepositoryProvider.overrideWithValue(bookings),
          rankingsRepositoryProvider.overrideWithValue(
            FakeRankingsRepository(rankings),
          ),
          tabsRepositoryProvider.overrideWithValue(
            FakeTabsRepository({'p1': 4435, 'p2': 0}),
          ),
          syncServiceProvider.overrideWithValue(sync),
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 11, 2, 21)),
          ),
          ...extra,
        ],
        child: MaterialApp(
          theme: theme ?? BarTabTheme.data,
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

  Future<void> open(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    expect(find.byType(DrinkSelectionScreen), findsOneWidget);
  }

  Finder tile(String drinkId) => find.byKey(ValueKey('drink-$drinkId'));

  Future<void> tapDrink(
    WidgetTester tester,
    String drinkId, [
    int n = 1,
  ]) async {
    for (var i = 0; i < n; i++) {
      await tester.tap(tile(drinkId));
      await tester.pump();
    }
  }

  /// Lets a commit finish and the route pop back to the name list.
  Future<void> settleRoute(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Lets the undo banner and the sync after the undo window run out.
  Future<void> outlastUndoWindow(WidgetTester tester) =>
      tester.pump(kUndoWindow + const Duration(seconds: 1));

  void expectOnNameList() {
    expect(find.byType(DrinkSelectionScreen), findsNothing);
    expect(find.text('Wer trinkt?'), findsOneWidget);
  }

  group('quick bar', () {
    const rankings = DrinkRankings(
      overall: {'d3': 9, 'd2': 5, 'j0': 4, 'j1': 3},
      persons: {
        'p1': {'d1': 1},
      },
    );
    Finder quick(String id) => find.byKey(ValueKey('quick-$id'));

    testWidgets('the quick bar shows own drinks first, then the overall ones', (
      tester,
    ) async {
      await pumpApp(tester, rankings: rankings);
      await open(tester, 'Kim Example');

      final ids = ['d1', 'd3', 'd2', 'j0'];
      for (final id in ids) {
        expect(quick(id), findsOneWidget);
      }
      expect(quick('j1'), findsNothing);
      final xs = [for (final id in ids) tester.getTopLeft(quick(id)).dx];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(xs.toSet().length, 4);
    });

    testWidgets('a quick tap books one unit and returns with the undo banner', (
      tester,
    ) async {
      await pumpApp(tester, rankings: rankings);
      await open(tester, 'Kim Example');

      await tester.tap(quick('d1'));
      await tester.pump();
      expect(find.byType(OrderBar), findsNothing);
      await settleRoute(tester);

      expectOnNameList();
      final booking = bookings.bookings.single;
      expect(booking.drinkId, 'd1');
      expect(booking.quantity, 1);
      expect(booking.unitPriceCents, 115);
      expect(find.text('Kim Example: 1× Lager gebucht'), findsOneWidget);

      await tester.tap(find.text('Rückgängig'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(bookings.bookings, isEmpty);
      await outlastUndoWindow(tester);
    });

    testWidgets(
      'a tap right after a quick booking does not open another person',
      (tester) async {
        await pumpApp(tester, rankings: rankings);
        await open(tester, 'Kim Example');

        await tester.tap(quick('d1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100)); // popping
        await tester.tap(find.text('Lou Sample'), warnIfMissed: false);
        await tester.pump();
        await settleRoute(tester);
        expectOnNameList();
        expect(find.byType(DrinkSelectionScreen), findsNothing);

        await tester.pump(kReturnTapGuard);
        await tester.tap(find.text('Lou Sample'));
        await tester.pumpAndSettle();
        expect(find.byType(DrinkSelectionScreen), findsOneWidget);
        expect(find.text('Guests'), findsOneWidget);
        await tester.pump(const Duration(seconds: 31));
        await outlastUndoWindow(tester);
      },
    );

    testWidgets('a double tap on a quick tile books once', (tester) async {
      await pumpApp(tester, rankings: rankings);
      await open(tester, 'Kim Example');

      await tester.tap(quick('d1'));
      await tester.tap(quick('d1'), warnIfMissed: false);
      await settleRoute(tester);

      expect(bookings.bookings, hasLength(1));
      await outlastUndoWindow(tester);
    });

    testWidgets(
      'the quick bar is greyed out and inert while a grid order is pending',
      (tester) async {
        await pumpApp(tester, rankings: rankings);
        await open(tester, 'Kim Example');

        await tapDrink(tester, 'd2');
        await tester.tap(quick('d3'), warnIfMissed: false);
        await tester.pump();
        expect(find.byType(DrinkSelectionScreen), findsOneWidget);
        expect(bookings.bookings, isEmpty);
        expect(find.byType(OrderBar), findsOneWidget);
        expect(find.text('1× Wheat'), findsOneWidget);

        await tester.tap(find.text('Verwerfen'));
        await tester.pump();
        await tester.tap(quick('d3'));
        await settleRoute(tester);

        expectOnNameList();
        expect(bookings.bookings.single.drinkId, 'd3');
        await outlastUndoWindow(tester);
      },
    );

    testWidgets('the quick bar stays bright but inert while a commit runs', (
      tester,
    ) async {
      final gate = Completer<void>();
      bookings.addAllGate = gate;
      await pumpApp(tester, rankings: rankings);
      await open(tester, 'Kim Example');
      double opacity() => tester
          .widget<Opacity>(
            find
                .ancestor(of: quick('d3'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;
      expect(opacity(), 1);

      await tester.tap(quick('d1'));
      await tester.pump();
      expect(opacity(), 1);
      await tester.tap(quick('d3'), warnIfMissed: false);
      await tester.pump();
      expect(bookings.bookings, isEmpty);

      gate.complete();
      await settleRoute(tester);
      await outlastUndoWindow(tester);
      expect(bookings.bookings.single.drinkId, 'd1');
    });

    testWidgets('the name list keeps the rankings warm for the drink screen', (
      tester,
    ) async {
      await pumpApp(tester, rankings: rankings);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NameListScreen)),
      );
      expect(container.read(rankingsProvider).hasValue, isTrue);
    });

    testWidgets('without rankings there is no quick bar', (tester) async {
      await pumpApp(tester);
      await open(tester, 'Kim Example');

      expect(find.byKey(const ValueKey('quick-d1')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              '${(w.key as ValueKey).value}'.startsWith('quick-'),
        ),
        findsNothing,
      );
      expect(tester.getTopLeft(tile('d1')).dy, lessThan(300));
    });
  });

  testWidgets('shows header, groups and tiles priced for the person', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');

    expect(find.text('Kim Example'), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('44,35$_nbsp€'), findsOneWidget);
    expect(find.text('seit der letzten Abrechnung'), findsOneWidget);
    expect(find.text('Andere Person'), findsOneWidget);

    expect(find.text('Beer'), findsOneWidget);
    expect(find.text('Soft'), findsOneWidget);
    expect(find.text('Secret Stash'), findsNothing);
    expect(
      find.descendant(of: tile('d1'), matching: find.text('Lager')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile('d1'), matching: find.text('1,15$_nbsp€')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile('d2'), matching: find.text('1,30$_nbsp€')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile('d3'), matching: find.text('0,60$_nbsp€')),
      findsOneWidget,
    );
    expect(find.text('Guest Special'), findsNothing);
    expect(find.text('Retired'), findsNothing);
    expect(find.text('Hidden Gin'), findsNothing);
    expect(find.byType(OrderBar), findsNothing);

    // Seven equal-width tiles per row; the eighth wraps.
    final soft = ['d3', for (var i = 0; i < 7; i++) 'j$i'];
    final firstRowTop = tester.getTopLeft(tile(soft[0])).dy;
    for (var i = 1; i < 7; i++) {
      expect(tester.getTopLeft(tile(soft[i])).dy, firstRowTop);
      expect(tester.getSize(tile(soft[i])), tester.getSize(tile(soft[0])));
    }
    expect(tester.getTopLeft(tile(soft[7])).dy, greaterThan(firstRowTop));
    // Groups top to bottom by sort order.
    expect(
      tester.getTopLeft(find.text('Beer')).dy,
      lessThan(tester.getTopLeft(find.text('Soft')).dy),
    );
  });

  testWidgets('prices follow the person tier', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Lou Sample');
    expect(find.text('Guests'), findsOneWidget);
    expect(
      find.descendant(of: tile('d1'), matching: find.text('1,50$_nbsp€')),
      findsOneWidget,
    );
    expect(find.text('Guest Special'), findsOneWidget);
    expect(find.text('Wheat'), findsNothing);
  });

  testWidgets('header shows a dash while the running total loads', (
    tester,
  ) async {
    await pumpApp(
      tester,
      extra: [
        runningTotalProvider('p1').overrideWithValue(const AsyncLoading()),
      ],
    );
    await open(tester, 'Kim Example');
    expect(find.text('–'), findsOneWidget);
  });

  testWidgets('taps count on the tiles and fill the order bar', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1', 2);
    await tapDrink(tester, 'd3');

    expect(
      find.descendant(of: tile('d1'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile('d3'), matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('2× Lager, 1× Lemonade'), findsOneWidget);
    expect(find.text('2,90$_nbsp€'), findsOneWidget);
    expect(find.text('wird in $delay Sekunden gebucht'), findsOneWidget);
    expect(find.text('Verwerfen'), findsOneWidget);
    expect(find.text('Fertig'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('wird in ${delay - 1} Sekunden gebucht'), findsOneWidget);
    await tester.pump(Duration(seconds: delay - 2));
    expect(find.text('wird in 1 Sekunde gebucht'), findsOneWidget);
    expect(bookings.bookings, isEmpty);
  });

  testWidgets('5 s after the last tap the order is booked', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');
    await tester.pump(kAutoBookDelay - const Duration(milliseconds: 100));
    expect(bookings.bookings, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    await settleRoute(tester);
    expect(bookings.bookings.single.drinkId, 'd1');
    expect(sync.syncNowCalls, 1);
    expectOnNameList();
    expect(find.text('Kim Example: 1× Lager gebucht'), findsOneWidget);
    await outlastUndoWindow(tester);
    expect(find.text('Kim Example: 1× Lager gebucht'), findsNothing);
  });

  testWidgets('the countdown bar is thick and spans the whole order bar', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');
    final track = find.byKey(const Key('order-bar-progress'));
    expect(tester.getSize(track).height, greaterThanOrEqualTo(10));
    expect(
      tester.getSize(track).width,
      tester.getSize(find.byType(OrderBar)).width,
    );
    await tester.tap(find.text('Verwerfen'));
    await tester.pump();
  });

  testWidgets(
    'the countdown bar drains evenly from full and a tap refills it',
    (tester) async {
      await pumpApp(tester);
      await open(tester, 'Kim Example');
      await tapDrink(tester, 'd1');
      final track = find.byKey(const Key('order-bar-progress'));
      final fill = find
          .descendant(of: track, matching: find.byType(ColoredBox))
          .last;
      double fraction() =>
          tester.getSize(fill).width / tester.getSize(track).width;

      expect(fraction(), closeTo(1, 0.01));
      await tester.pump(const Duration(milliseconds: 500));
      expect(fraction(), closeTo(0.9, 0.02));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(fraction(), closeTo(0.5, 0.02));

      await tapDrink(tester, 'd3');
      expect(fraction(), closeTo(1, 0.01));
      await tester.pump(const Duration(milliseconds: 2500));
      expect(fraction(), closeTo(0.5, 0.02));
      await tester.pump(const Duration(milliseconds: 2400));
      expect(fraction(), closeTo(0.02, 0.02));
      expect(bookings.bookings, isEmpty);

      await tester.pump(const Duration(milliseconds: 100));
      await settleRoute(tester);
      expect(find.byType(OrderBar), findsNothing);
      expect(bookings.bookings, hasLength(2));
      await outlastUndoWindow(tester);
    },
  );

  testWidgets('Verwerfen clears the bar and books nothing', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1', 2);
    await tester.tap(find.text('Verwerfen'));
    await tester.pump();
    expect(find.byType(OrderBar), findsNothing);
    expect(
      find.descendant(of: tile('d1'), matching: find.text('2')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 30));
    expect(bookings.bookings, isEmpty);
    expect(find.byType(DrinkSelectionScreen), findsOneWidget);
  });

  testWidgets('Fertig books, returns, and the total includes the booking', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1', 2);
    await tapDrink(tester, 'd3');
    await tester.tap(find.text('Fertig'));
    await settleRoute(tester);

    expect(
      bookings.bookings.map((b) => (b.drinkId, b.quantity, b.unitPriceCents)),
      [('d1', 2, 115), ('d3', 1, 60)],
    );
    expectOnNameList();
    expect(
      find.text('Kim Example: 2× Lager, 1× Lemonade gebucht'),
      findsOneWidget,
    );

    await open(tester, 'Kim Example');
    // 44,35 € + 2,90 €
    expect(find.text('47,25$_nbsp€'), findsOneWidget);
    await outlastUndoWindow(tester);
  });

  testWidgets('3rd tap opens the sheet; keypad 24 and Weitere Getränke', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1', 2);
    expect(find.byType(QuantitySheet), findsNothing);
    await tapDrink(tester, 'd1');
    expect(find.byType(QuantitySheet), findsOneWidget);
    expect(find.text('Anzahl, je 1,15$_nbsp€'), findsOneWidget);
    expect(find.text('Kasten (20)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('keypad-2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('keypad-4')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(QuantitySheet.fieldKey),
        matching: find.text('24'),
      ),
      findsOneWidget,
    );
    // Sheet open: no auto-booking.
    await tester.pump(const Duration(seconds: 29));
    expect(bookings.bookings, isEmpty);

    await tester.tap(find.text('Weitere Getränke'));
    await tester.pump();
    expect(find.byType(QuantitySheet), findsNothing);
    expect(
      find.descendant(of: tile('d1'), matching: find.text('24')),
      findsOneWidget,
    );
    expect(find.text('24× Lager'), findsOneWidget);
    expect(find.text('wird in $delay Sekunden gebucht'), findsOneWidget);
    expect(bookings.bookings, isEmpty);
  });

  testWidgets('Kasten sets the crate size and Buchen books the order', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd3');
    await tapDrink(tester, 'd1', 3);
    await tester.tap(find.text('Kasten (20)'));
    await tester.pump();
    // 20 × 1,15 € + 0,60 €
    expect(find.text('23,60$_nbsp€'), findsOneWidget);
    await tester.tap(find.text('Buchen'));
    await settleRoute(tester);

    expect(bookings.bookings.map((b) => (b.drinkId, b.quantity)), [
      ('d3', 1),
      ('d1', 20),
    ]);
    expectOnNameList();
    expect(
      find.text('Kim Example: 1× Lemonade, 20× Lager gebucht'),
      findsOneWidget,
    );
    await outlastUndoWindow(tester);
  });

  testWidgets('quantity 0 and Weitere Getränke removes the line', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1', 3);
    await tester.tap(find.byKey(const Key('keypad-0')));
    await tester.pump();
    await tester.tap(find.text('Weitere Getränke'));
    await tester.pump();
    expect(find.byType(OrderBar), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(bookings.bookings, isEmpty);
  });

  testWidgets('Andere Person books a pending order, then returns', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd2');
    await tester.tap(find.text('Andere Person'));
    await settleRoute(tester);
    expect(bookings.bookings.single.drinkId, 'd2');
    expectOnNameList();
    await outlastUndoWindow(tester);
  });

  testWidgets('Andere Person with nothing tapped just returns', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tester.tap(find.text('Andere Person'));
    await settleRoute(tester);
    expect(bookings.bookings, isEmpty);
    expect(sync.syncNowCalls, 0);
    expectOnNameList();
    expect(find.textContaining('gebucht'), findsNothing);
  });

  testWidgets('app going to the background books a pending order', (
    tester,
  ) async {
    // Lifecycle listeners only accept single-step transitions.
    void go(List<AppLifecycleState> states) {
      for (final s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
    }

    const toBackground = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    const toForeground = [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ];
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1', 2);
    go(toBackground);
    await tester.pump();
    expect(bookings.bookings.single.quantity, 2);
    // Frames resume in the foreground; the screen has already left.
    go(toForeground);
    await settleRoute(tester);
    expectOnNameList();
    await outlastUndoWindow(tester);
  });

  testWidgets('a price change after the tap keeps the tap-time price', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');

    catalog = testCatalog(lagerPrice: 200);
    ProviderScope.containerOf(
      tester.element(find.byType(DrinkSelectionScreen)),
    ).invalidate(catalogProvider);
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: tile('d1'), matching: find.text('2,00$_nbsp€')),
      findsOneWidget,
    );

    await tapDrink(tester, 'd1');
    await tester.tap(find.text('Fertig'));
    await settleRoute(tester);
    final b = bookings.bookings.single;
    expect((b.quantity, b.unitPriceCents), (2, 115));
    await outlastUndoWindow(tester);
  });

  testWidgets('leaving the name list cancels the banner timer', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');
    await tester.tap(find.text('Fertig'));
    await settleRoute(tester);
    expect(find.text('Kim Example: 1× Lager gebucht'), findsOneWidget);
    // Disposing the tree must not leave the banner or sync timer pending.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('system back books a pending order, then returns', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd2');
    await tester.binding.handlePopRoute();
    await settleRoute(tester);
    expect(bookings.bookings.single.drinkId, 'd2');
    expectOnNameList();
    expect(find.text('Kim Example: 1× Wheat gebucht'), findsOneWidget);
    await outlastUndoWindow(tester);
  });

  testWidgets('system back with nothing tapped just returns', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tester.binding.handlePopRoute();
    await settleRoute(tester);
    expect(bookings.bookings, isEmpty);
    expectOnNameList();
  });

  testWidgets('a failed write shows a retry hint and is retried', (
    tester,
  ) async {
    bookings.addAllError = StateError('disk full');
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');
    await tester.tap(find.text('Fertig'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Speichern fehlgeschlagen – neuer Versuch …'),
      findsOneWidget,
    );
    expect(find.textContaining('Sekunde'), findsNothing);
    expect(find.byType(DrinkSelectionScreen), findsOneWidget);

    bookings.addAllError = null;
    await tester.pump(kAutoBookDelay);
    await settleRoute(tester);
    expect(bookings.bookings.single.drinkId, 'd1');
    expectOnNameList();
    await outlastUndoWindow(tester);
  });

  testWidgets('sheet hides the crate key when the drink left the catalog', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1', 3);
    expect(find.text('Kasten (20)'), findsOneWidget);

    final full = testCatalog();
    catalog = full.copyWith(
      drinks: [
        for (final d in full.drinks)
          if (d.id != 'd1') d,
      ],
    );
    ProviderScope.containerOf(
      tester.element(find.byType(DrinkSelectionScreen)),
    ).invalidate(catalogProvider);
    await tester.pump();
    await tester.pump();
    expect(find.byType(QuantitySheet), findsOneWidget);
    expect(find.byKey(const Key('keypad-crate')), findsNothing);
    expect(find.textContaining('Kasten'), findsNothing);
  });

  testWidgets('a drink deactivated while pending still books at its price', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');
    expect(find.text('1× Lager'), findsOneWidget);

    final full = testCatalog(lagerPrice: 999);
    catalog = full.copyWith(
      drinks: [
        for (final d in full.drinks)
          if (d.id == 'd1') d.copyWith(isActive: false) else d,
      ],
    );
    ProviderScope.containerOf(
      tester.element(find.byType(DrinkSelectionScreen)),
    ).invalidate(catalogProvider);
    await tester.pump();
    await tester.pump();
    expect(tile('d1'), findsNothing);
    expect(find.text('1× Lager'), findsOneWidget);

    await tester.pump(kAutoBookDelay);
    await settleRoute(tester);
    expectOnNameList();
    final booking = bookings.bookings.single;
    expect(booking.drinkId, 'd1');
    expect(booking.unitPriceCents, 115);
    await outlastUndoWindow(tester);
  });

  testWidgets('re-opening the person while the old screen pops starts clean', (
    tester,
  ) async {
    await pumpApp(tester);
    final nameAt = tester.getCenter(find.text('Kim Example'));
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');
    await tester.tap(find.text('Fertig'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // popping

    await tester.tapAt(nameAt);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.byType(DrinkSelectionScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(find.byType(DrinkSelectionScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await settleRoute(tester);
    expectOnNameList();
    expect(bookings.bookings, hasLength(1));
  });

  testWidgets('system back on the name list does not exit the app', (
    tester,
  ) async {
    await pumpApp(tester);
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expectOnNameList();
    // handlePopRoute returns false when nothing consumed it (app would exit).
    expect(handled, isTrue);
  });

  testWidgets('back during a failing write keeps the order and retries', (
    tester,
  ) async {
    final gate = Completer<void>();
    bookings
      ..addAllGate = gate
      ..addAllError = StateError('disk full');
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');
    await tester.tap(find.text('Fertig'));
    await tester.pump();

    // Write still in flight: back must not leave.
    await tester.binding.handlePopRoute();
    await settleRoute(tester);
    expect(find.byType(DrinkSelectionScreen), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Speichern fehlgeschlagen – neuer Versuch …'),
      findsOneWidget,
    );
    expect(find.text('1× Lager'), findsOneWidget);

    bookings
      ..addAllGate = null
      ..addAllError = null;
    await tester.pump(kAutoBookDelay);
    await settleRoute(tester);
    expect(bookings.bookings.single.drinkId, 'd1');
    expectOnNameList();
    await outlastUndoWindow(tester);
  });

  group('idle timeouts', () {
    Future<void> openSheetOnLager(WidgetTester tester) async {
      await open(tester, 'Kim Example');
      await tapDrink(tester, 'd1', 3);
      expect(find.byType(QuantitySheet), findsOneWidget);
    }

    testWidgets('empty draft: leaves without booking after 30 s', (
      tester,
    ) async {
      await pumpApp(tester);
      await open(tester, 'Kim Example');
      await tester.pump(const Duration(seconds: 29));
      expect(find.byType(DrinkSelectionScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await settleRoute(tester);
      expectOnNameList();
      expect(bookings.bookings, isEmpty);
      expect(find.textContaining('gebucht'), findsNothing);
    });

    testWidgets('a tap on empty space restarts the 30 s', (tester) async {
      await pumpApp(tester);
      await open(tester, 'Kim Example');
      await tester.pump(const Duration(seconds: 20));
      await tester.tapAt(const Offset(2, 400));
      await tester.pump(const Duration(seconds: 29));
      expect(find.byType(DrinkSelectionScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await settleRoute(tester);
      expectOnNameList();
    });

    testWidgets('Verwerfen restarts the 30 s', (tester) async {
      await pumpApp(tester);
      await open(tester, 'Kim Example');
      await tapDrink(tester, 'd1');
      await tester.pump(kAutoBookDelay - const Duration(seconds: 1));
      await tester.tap(find.text('Verwerfen'));
      await tester.pump(const Duration(seconds: 29));
      expect(find.byType(DrinkSelectionScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await settleRoute(tester);
      expectOnNameList();
      expect(bookings.bookings, isEmpty);
    });

    testWidgets('untouched sheet closes at 30 s, books 5 s later', (
      tester,
    ) async {
      await pumpApp(tester);
      await openSheetOnLager(tester);
      await tester.pump(const Duration(seconds: 29));
      expect(find.byType(QuantitySheet), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(QuantitySheet), findsNothing);
      expect(bookings.bookings, isEmpty);
      await tester.pump(kAutoBookDelay);
      await settleRoute(tester);
      expect(bookings.bookings.single.quantity, 3);
      expectOnNameList();
      await outlastUndoWindow(tester);
    });

    testWidgets('a key press restarts the sheet idle timer', (tester) async {
      await pumpApp(tester);
      await openSheetOnLager(tester);
      await tester.pump(const Duration(seconds: 25));
      await tester.tap(find.byKey(const Key('keypad-5')));
      await tester.pump(const Duration(seconds: 29));
      expect(find.byType(QuantitySheet), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(QuantitySheet), findsNothing);
      await tester.pump(kAutoBookDelay);
      await settleRoute(tester);
      expect(bookings.bookings.single.quantity, 5);
      await outlastUndoWindow(tester);
    });
  });

  forEachDesign((design) {
    testWidgets('the header takes the design colours and fonts', (
      tester,
    ) async {
      final tokens = tokensFor(design);
      await pumpApp(tester, theme: themeFor(design));
      await open(tester, 'Kim Example');
      TextStyle style(String text) =>
          tester.widget<Text>(find.text(text)).style!;
      expect(style('Kim Example').color, tokens.text);
      expect(style('Kim Example').fontFamily, tokens.displayFont);
      expect(style('Members').color, tokens.muted);
      expect(style('Members').fontFamily, tokens.bodyFont);
    });
  });
}
