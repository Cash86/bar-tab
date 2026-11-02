import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/drinks/drink_selection_screen.dart';
import 'package:bar_tab/presentation/drinks/order_bar.dart';
import 'package:bar_tab/presentation/drinks/quantity_sheet.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

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

  setUp(() {
    bookings = FakeBookingRepository();
    sync = FakeSyncService();
    catalog = testCatalog();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    List<Override> extra = const [],
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

  void expectOnNameList() {
    expect(find.byType(DrinkSelectionScreen), findsNothing);
    expect(find.text('Wer trinkt?'), findsOneWidget);
  }

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
    expect(find.text('wird in 8 Sekunden gebucht'), findsOneWidget);
    expect(find.text('Verwerfen'), findsOneWidget);
    expect(find.text('Fertig'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('wird in 7 Sekunden gebucht'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('wird in 1 Sekunde gebucht'), findsOneWidget);
    expect(bookings.bookings, isEmpty);
  });

  testWidgets('8 s after the last tap the order is booked', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');
    await tester.pump(const Duration(seconds: 8));
    await settleRoute(tester);
    expect(bookings.bookings.single.drinkId, 'd1');
    expect(sync.syncNowCalls, 1);
    expectOnNameList();
    expect(find.text('Gebucht: 1× Lager'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Gebucht: 1× Lager'), findsNothing);
  });

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
    expect(find.text('Gebucht: 2× Lager, 1× Lemonade'), findsOneWidget);

    await open(tester, 'Kim Example');
    // 44,35 € + 2,90 €
    expect(find.text('47,25$_nbsp€'), findsOneWidget);
    // Let the banner timer run out.
    await tester.pump(const Duration(seconds: 3));
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
    await tester.pump(const Duration(seconds: 30));
    expect(bookings.bookings, isEmpty);

    await tester.tap(find.text('Weitere Getränke'));
    await tester.pump();
    expect(find.byType(QuantitySheet), findsNothing);
    expect(
      find.descendant(of: tile('d1'), matching: find.text('24')),
      findsOneWidget,
    );
    expect(find.text('24× Lager'), findsOneWidget);
    expect(find.text('wird in 8 Sekunden gebucht'), findsOneWidget);
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
    expect(find.text('Gebucht: 1× Lemonade, 20× Lager'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
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
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Andere Person with nothing tapped just returns', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tester.tap(find.text('Andere Person'));
    await settleRoute(tester);
    expect(bookings.bookings, isEmpty);
    expect(sync.syncNowCalls, 0);
    expectOnNameList();
    expect(find.textContaining('Gebucht'), findsNothing);
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
    await tester.pump(const Duration(seconds: 3));
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
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('leaving the name list cancels the banner timer', (tester) async {
    await pumpApp(tester);
    await open(tester, 'Kim Example');
    await tapDrink(tester, 'd1');
    await tester.tap(find.text('Fertig'));
    await settleRoute(tester);
    expect(find.text('Gebucht: 1× Lager'), findsOneWidget);
    // Disposing the tree must not leave the 3 s timer pending.
    await tester.pumpWidget(const SizedBox());
  });
}
