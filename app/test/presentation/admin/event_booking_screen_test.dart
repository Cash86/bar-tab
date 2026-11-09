import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/admin_session.dart';
import 'package:bar_tab/presentation/admin/event_booking_screen.dart';
import 'package:bar_tab/presentation/format.dart';
import 'package:bar_tab/presentation/kiosk.dart';
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

class _SpySync extends SyncService {
  _SpySync({
    required super.api,
    required super.bookings,
    required super.clock,
    required this.calls,
  }) : super(
         tabs: FakeTabsRepository(),
         catalog: _NoCatalog(),
         rankings: FakeRankingsRepository(),
         transaction: (action) => action(),
       );

  final List<String> calls;

  /// A sync already in flight (e.g. the periodic one), finished by the test.
  Completer<void>? running;

  @override
  bool get isSyncing => running != null;

  @override
  Future<void> syncNow() async {
    calls.add('syncNow');
    // Like the real service: a call while one runs joins it.
    if (running case final r?) {
      await r.future;
      running = null;
    }
  }
}

Person _person(
  String id,
  String name,
  String tier, {
  bool hidden = false,
  bool collective = false,
  bool active = true,
}) => Person(
  id: id,
  name: name,
  priceTierId: tier,
  isHidden: hidden,
  isCollective: collective,
  isActive: active,
);

Drink _drink(
  String id,
  String name, {
  int crate = 20,
  bool active = true,
  bool hidden = false,
  bool keg = false,
  Map<String, int> prices = const {'t1': 100, 't2': 150},
}) => Drink(
  id: id,
  name: name,
  groupId: 'g1',
  crateSize: crate,
  sortOrder: 1,
  isHidden: hidden,
  isKeg: keg,
  isActive: active,
  prices: prices,
);

const _idle = Duration(seconds: 10);

void main() {
  late FakeApiServer server;
  late FixedClock clock;
  late FakeBookingRepository queue;
  late Future<http.Response> Function(http.Request r) onBookings;
  late List<String> syncCalls;

  final catalog = Catalog(
    tiers: const [
      PriceTier(id: 't1', name: 'Members', sortOrder: 1),
      PriceTier(id: 't2', name: 'AH', sortOrder: 2),
    ],
    persons: [
      _person('p1', 'Zoe', 't1'),
      _person('p2', 'Anna', 't1'),
      _person('p3', 'Gruppe', 't1', collective: true),
      _person('p4', 'Hans', 't2', hidden: true),
      _person('p5', 'Ehemalig', 't1', active: false),
      _person('p6', 'Bruno', 't1', hidden: true, collective: true),
    ],
    groups: const [
      DrinkGroup(id: 'g1', name: 'Bier', sortOrder: 1, color: 0xFFFFC107),
    ],
    drinks: [
      _drink('d1', 'Pils'),
      _drink('d2', 'Wasser', crate: 1),
      _drink('d3', 'Alt Old', active: false),
      _drink('d4', 'Geheim', hidden: true),
      _drink(
        'd6',
        'Fass 30l',
        keg: true,
        crate: 1,
        prices: const {'t1': 12000, 't2': 13050},
      ),
      _drink('d7', 'Fass leer', keg: true, crate: 1, prices: const {}),
      _drink('d5', 'Nur Mitglieder', crate: 1, prices: const {'t1': 90}),
    ],
    etag: 'e',
  );

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    queue = FakeBookingRepository(clock: clock);
    syncCalls = [];
    onBookings = (r) async {
      final items =
          (jsonDecode(r.body) as Map<String, dynamic>)['bookings'] as List;
      return _json({
        'results': [
          for (final i in items)
            {'id': (i as Map<String, dynamic>)['id'], 'status': 'accepted'},
        ],
      });
    };
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (r.method == 'POST' &&
          path.endsWith('/bookings') &&
          r is http.Request) {
        return onBookings(r);
      }
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

  Future<void> openEvent(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(pairedStore()),
          httpClientProvider.overrideWithValue(server.client),
          clockProvider.overrideWithValue(clock),
          idleTimeoutProvider.overrideWithValue(_idle),
          catalogProvider.overrideWith((ref) async => catalog),
          rankingsProvider.overrideWith((ref) => Stream.value(null)),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          syncServiceProvider.overrideWith(
            (ref) => _SpySync(
              api: ref.watch(apiProvider)!,
              bookings: queue,
              clock: clock,
              calls: syncCalls,
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
    for (final d in '1234'.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-tile-event')));
    await tester.pumpAndSettle();
    expect(find.byType(EventBookingScreen), findsOneWidget);
  }

  Future<void> pick(WidgetTester tester, String personId) async {
    await tester.tap(find.byKey(Key('event-person-$personId')));
    await tester.pumpAndSettle();
  }

  Future<void> typeDigits(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
  }

  Future<void> enter(
    WidgetTester tester,
    String drinkId, {
    String crates = '',
    String units = '',
  }) async {
    await tester.tap(find.byKey(Key('qty-row-$drinkId')));
    await tester.pump();
    await typeDigits(tester, crates);
    if (units.isNotEmpty) {
      final chip = find.byKey(const Key('qty-chip-units'));
      if (chip.evaluate().isNotEmpty) await tester.tap(chip);
      await tester.pump();
      await typeDigits(tester, units);
    }
  }

  Finder submit() => find.byKey(const Key('event-submit'));

  List<http.Request> bookingRequests() => server.requests
      .whereType<http.Request>()
      .where((r) => r.method == 'POST' && r.url.path.endsWith('/bookings'))
      .toList();

  List<Map<String, dynamic>> items(http.Request r) =>
      ((jsonDecode(r.body) as Map<String, dynamic>)['bookings'] as List)
          .cast<Map<String, dynamic>>();

  Future<void> book(WidgetTester tester) async {
    await tester.tap(submit());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('the picker lists hidden, then collective, then the rest', (
    tester,
  ) async {
    await openEvent(tester);
    expect(find.text('Person wählen'), findsOneWidget);
    expect(find.text('Ehemalig'), findsNothing);
    final ids = [
      for (final w in tester.widgetList(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('event-person-'),
        ),
      ))
        (w.key! as ValueKey<String>).value.substring('event-person-'.length),
    ];
    expect(ids, ['p6', 'p4', 'p3', 'p2', 'p1']);
    expect(
      find.descendant(
        of: find.byKey(const Key('event-person-p4')),
        matching: find.text('AH'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('step 2 shows the person, tier prices and the sum', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p4');
    expect(find.text('Person: Hans · AH'), findsOneWidget);
    expect(find.text('Alt Old'), findsNothing);
    expect(find.text('Geheim'), findsOneWidget);
    expect(find.text('Fass 30l'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isFalse);
    await enter(tester, 'd1', crates: '1');
    await enter(tester, 'd2', units: '2');
    // 20 x 1,50 = 30,00; 2 x 1,50 = 3,00.
    expect(find.text(formatCents(3000)), findsOneWidget);
    expect(find.text(formatCents(300)), findsOneWidget);
    expect(find.text('Buchen · ${formatCents(3300)}'), findsOneWidget);
  });

  testWidgets('a hidden drink for a hidden person goes out at the AH price', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p4');
    await enter(tester, 'd4', crates: '1');
    await tester.tap(submit());
    await tester.pumpAndSettle();
    expect(
      find.text('Hans: 1 Getränk für ${formatCents(3000)} buchen?'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('event-confirm')));
    await tester.pumpAndSettle();
    final sent = items(bookingRequests().single).single;
    expect(sent['person_id'], 'p4');
    expect(sent['drink_id'], 'd4');
    expect(sent['quantity'], 20);
    expect(sent['unit_price_cents'], 150);
    expect(DateTime.parse(sent['booked_at'] as String), clock.now());
    expect(find.text('Veranstaltung gebucht'), findsOneWidget);
    expect(find.byType(EventBookingScreen), findsNothing);
  });

  testWidgets('success syncs and never touches the local queue', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd2', units: '3');
    await book(tester);
    expect(syncCalls, ['syncNow']);
    expect(queue.bookings, isEmpty);
  });

  testWidgets('a sync in flight is awaited, then one more runs', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd2', units: '3');
    final running = Completer<void>();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EventBookingScreen)),
    );
    (container.read(syncServiceProvider)! as _SpySync).running = running;
    await book(tester);
    // Joined the running sync, which may have fetched tabs before the write.
    expect(syncCalls, ['syncNow']);
    running.complete();
    await tester.pumpAndSettle();
    expect(syncCalls, ['syncNow', 'syncNow']);
  });

  testWidgets('a duplicate counts as success', (tester) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd2', units: '3');
    onBookings = (r) async => _json({
      'results': [
        for (final i in items(r)) {'id': i['id'], 'status': 'duplicate'},
      ],
    });
    await book(tester);
    expect(find.byType(EventBookingScreen), findsNothing);
  });

  testWidgets('a rejected line shows the failure toast and stays', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd2', units: '3');
    onBookings = (r) async => _json({
      'results': [
        for (final i in items(r))
          {'id': i['id'], 'status': 'rejected', 'reason': 'invalid_price'},
      ],
    });
    await book(tester);
    expect(find.text('Buchung nicht möglich'), findsOneWidget);
    expect(find.byType(EventBookingScreen), findsOneWidget);
    expect(find.text('= 3'), findsOneWidget);
    expect(syncCalls, isEmpty);
  });

  testWidgets('a conflict shows the failure toast and stays', (tester) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd2', units: '3');
    onBookings = (r) async => _json({
      'results': [
        for (final i in items(r)) {'id': i['id'], 'status': 'conflict'},
      ],
    });
    await book(tester);
    expect(find.text('Buchung nicht möglich'), findsOneWidget);
    expect(find.byType(EventBookingScreen), findsOneWidget);
  });

  testWidgets('cancelling the confirmation sends nothing', (tester) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd2', units: '3');
    await tester.tap(submit());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(bookingRequests(), isEmpty);
    expect(find.byType(EventBookingScreen), findsOneWidget);
  });

  testWidgets('network failure keeps values; retry sends the same ids', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd1', crates: '1');
    await enter(tester, 'd2', units: '6');
    var fail = true;
    final ok = onBookings;
    onBookings = (r) async => fail ? throw http.ClientException('down') : ok(r);
    await book(tester);
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    expect(find.byType(EventBookingScreen), findsOneWidget);
    expect(find.text('= 20'), findsOneWidget);
    fail = false;
    await tester.pump(const Duration(seconds: 5));
    await book(tester);
    final reqs = bookingRequests();
    expect(reqs.length, 2);
    expect(items(reqs[1]), items(reqs[0]));
    expect({for (final i in items(reqs[0])) i['id']}, hasLength(2));
    expect(find.byType(EventBookingScreen), findsNothing);
  });

  testWidgets('an edited line gets a new id, an unchanged one keeps it', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd1', crates: '1');
    await enter(tester, 'd2', units: '6');
    var fail = true;
    final ok = onBookings;
    onBookings = (r) async => fail ? throw http.ClientException('down') : ok(r);
    await book(tester);
    await tester.tap(find.byKey(const Key('qty-row-d1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('qty-chip-units')));
    await tester.pump();
    await typeDigits(tester, '1');
    fail = false;
    clock.advance(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 5));
    await book(tester);
    final reqs = bookingRequests();
    Map<String, Map<String, dynamic>> byDrink(http.Request r) => {
      for (final i in items(r)) i['drink_id'] as String: i,
    };
    final first = byDrink(reqs[0]);
    final second = byDrink(reqs[1]);
    expect(second['d1']!['quantity'], 21);
    expect(second['d1']!['id'], isNot(first['d1']!['id']));
    expect(second['d2']!['id'], first['d2']!['id']);
    // The unchanged line keeps its time too; the edited one is booked now.
    expect(second['d2']!['booked_at'], first['d2']!['booked_at']);
    expect(DateTime.parse(second['d1']!['booked_at'] as String), clock.now());
  });

  testWidgets('a retry after a lost answer is a duplicate, even later', (
    tester,
  ) async {
    // Like the server: a known id with the same content is a duplicate,
    // with other content (booked_at included) a conflict.
    final stored = <String, String>{};
    var loseAnswer = true;
    onBookings = (r) async {
      final results = [
        for (final i in items(r))
          {
            'id': i['id'],
            'status': switch (stored[i['id']]) {
              null => 'accepted',
              final s when s == jsonEncode(i) => 'duplicate',
              _ => 'conflict',
            },
          },
      ];
      for (final i in items(r)) {
        stored.putIfAbsent(i['id'] as String, () => jsonEncode(i));
      }
      if (loseAnswer) {
        loseAnswer = false;
        throw http.ClientException('answer lost');
      }
      return _json({'results': results});
    };
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd1', crates: '1');
    await enter(tester, 'd2', units: '6');
    await book(tester);
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    clock.advance(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 5));
    await book(tester);
    expect(find.text('Buchung nicht möglich'), findsNothing);
    expect(find.text('Veranstaltung gebucht'), findsOneWidget);
    expect(find.byType(EventBookingScreen), findsNothing);
  });

  testWidgets('a line without a price for the tier blocks booking', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p4');
    await enter(tester, 'd1', crates: '1');
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isTrue);
    expect(find.text('Kein Preis für AH: Nur Mitglieder'), findsNothing);
    await enter(tester, 'd5', units: '2');
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isFalse);
    expect(find.text('Kein Preis für AH: Nur Mitglieder'), findsOneWidget);
    await tester.tap(submit());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(bookingRequests(), isEmpty);
  });

  testWidgets('"Person ändern" returns to the picker and clears the lines', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd2', units: '3');
    await tester.tap(find.text('Person ändern'));
    await tester.pumpAndSettle();
    expect(find.text('Person wählen'), findsOneWidget);
    await pick(tester, 'p1');
    expect(find.text('Person: Zoe · Members'), findsOneWidget);
    expect(find.text('= 3'), findsNothing);
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isFalse);
  });

  testWidgets('a line cannot exceed 999 units', (tester) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd2', units: '999');
    expect(find.text('= 999'), findsOneWidget);
    await typeDigits(tester, '1');
    expect(find.text('= 999'), findsOneWidget);
    // 49 crates of 20 = 980; one more crate digit would pass 999.
    await enter(tester, 'd1', crates: '49');
    expect(find.text('= 980'), findsOneWidget);
    await typeDigits(tester, '9');
    expect(find.text('= 980'), findsOneWidget);
  });

  testWidgets('a session ending under the confirmation leaves cleanly', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await enter(tester, 'd2', units: '3');
    await tester.tap(submit());
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EventBookingScreen)),
    );
    await container.read(adminSessionProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.byType(EventBookingScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('admin-pin-login')), findsOneWidget);
    expect(bookingRequests(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('idle on the picker logs out to the name list', (tester) async {
    await openEvent(tester);
    await tester.pump(_idle);
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.byType(EventBookingScreen), findsNothing);
  });

  testWidgets('idle on the quantity step logs out to the name list', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p2');
    await tester.pump(_idle);
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.byType(EventBookingScreen), findsNothing);
  });

  Finder kegPrice(String id) => find.byKey(Key('event-keg-price-$id'));

  testWidgets('a keg line shows its tier price in a labelled field', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p4');
    expect(kegPrice('d6'), findsNothing);
    await enter(tester, 'd6', units: '1');
    expect(kegPrice('d6'), findsOneWidget);
    expect(find.text('Einkaufspreis'), findsOneWidget);
    expect(tester.widget<TextField>(kegPrice('d6')).controller!.text, '130,50');
    await enter(tester, 'd1', units: '1');
    expect(kegPrice('d1'), findsNothing);
  });

  testWidgets('a keg without a tier price starts empty and blocks booking', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p1');
    await enter(tester, 'd7', units: '1');
    expect(tester.widget<TextField>(kegPrice('d7')).controller!.text, '');
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isFalse);
    await tester.enterText(kegPrice('d7'), 'abc');
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isFalse);
    await tester.enterText(kegPrice('d7'), '99,5');
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isTrue);
  });

  testWidgets('the entered keg price is sent as the unit price', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p1');
    await enter(tester, 'd6', units: '2');
    await enter(tester, 'd2', units: '1');
    await tester.enterText(kegPrice('d6'), '99,5');
    await tester.pump();
    expect(
      find.text('Buchen · ${formatCents(2 * 9950 + 100)}'),
      findsOneWidget,
    );
    await book(tester);
    final byDrink = {
      for (final i in items(bookingRequests().single)) i['drink_id']: i,
    };
    expect(byDrink['d6']!['unit_price_cents'], 9950);
    expect(byDrink['d6']!['quantity'], 2);
    expect(byDrink['d2']!['unit_price_cents'], 100);
  });

  testWidgets('a keg price of 0,00 is allowed', (tester) async {
    await openEvent(tester);
    await pick(tester, 'p1');
    await enter(tester, 'd7', units: '1');
    await tester.enterText(kegPrice('d7'), '0,00');
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isTrue);
    await book(tester);
    expect(items(bookingRequests().single).single['unit_price_cents'], 0);
  });

  testWidgets('a keg with quantity 0 does not block booking', (tester) async {
    await openEvent(tester);
    await pick(tester, 'p1');
    await enter(tester, 'd2', units: '1');
    await enter(tester, 'd7', units: '0');
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isTrue);
  });

  testWidgets('choosing another person fills the keg price again', (
    tester,
  ) async {
    await openEvent(tester);
    await pick(tester, 'p1');
    await enter(tester, 'd6', units: '1');
    await tester.enterText(kegPrice('d6'), '5');
    await tester.tap(find.byKey(const Key('event-change-person')));
    await tester.pumpAndSettle();
    await pick(tester, 'p4');
    await enter(tester, 'd6', units: '1');
    expect(tester.widget<TextField>(kegPrice('d6')).controller!.text, '130,50');
  });
}
