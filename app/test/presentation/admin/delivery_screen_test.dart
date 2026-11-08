import 'dart:convert';

import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/delivery_screen.dart';
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

Drink _drink(
  String id,
  String name, {
  int crate = 20,
  bool active = true,
  bool hidden = false,
}) => Drink(
  id: id,
  name: name,
  groupId: 'g1',
  crateSize: crate,
  sortOrder: 1,
  isHidden: hidden,
  isActive: active,
  prices: const {'t1': 100},
);

void main() {
  late FakeApiServer server;
  late FixedClock clock;
  late Future<http.Response> Function(http.Request r) onDelivery;

  final catalog = Catalog(
    tiers: const [PriceTier(id: 't1', name: 'Members', sortOrder: 1)],
    persons: const [],
    groups: const [
      DrinkGroup(id: 'g1', name: 'Bier', sortOrder: 1, color: 0xFFFFC107),
    ],
    drinks: [
      _drink('d1', 'Pils'),
      _drink('d2', 'Wasser', crate: 1),
      _drink('d3', 'Alt Old', active: false),
      _drink('d4', 'Geheim', hidden: true),
    ],
    etag: 'e',
  );

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    onDelivery = (r) async {
      final items =
          (jsonDecode(r.body) as Map<String, dynamic>)['deliveries'] as List;
      return _json({
        'deliveries': [
          for (final i in items)
            {
              ...(i as Map<String, dynamic>),
              'created_at': '2026-11-05T21:00:00Z',
              'cancelled_at': null,
            },
        ],
      }, 201);
    };
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (path.endsWith('admin/deliveries') && r is http.Request) {
        return onDelivery(r);
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

  Future<void> openDelivery(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(pairedStore()),
          httpClientProvider.overrideWithValue(server.client),
          clockProvider.overrideWithValue(clock),
          catalogProvider.overrideWith((ref) async => catalog),
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
    for (final d in '1234'.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-tile-delivery')));
    await tester.pumpAndSettle();
    expect(find.byType(DeliveryScreen), findsOneWidget);
  }

  Future<void> typeDigits(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
  }

  /// Selects the row of [drinkId], then types crates and/or units.
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

  Finder submit() => find.byKey(const Key('delivery-submit'));

  List<http.Request> deliveryRequests() => server.requests
      .whereType<http.Request>()
      .where((r) => r.url.path.endsWith('admin/deliveries'))
      .toList();

  List<Map<String, dynamic>> items(http.Request r) =>
      ((jsonDecode(r.body) as Map<String, dynamic>)['deliveries'] as List)
          .cast<Map<String, dynamic>>();

  Future<void> book(WidgetTester tester) async {
    await tester.tap(submit());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delivery-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('the button is disabled while all quantities are zero', (
    tester,
  ) async {
    await openDelivery(tester);
    expect(tester.widget<ButtonStyleButton>(submit()).enabled, isFalse);
    expect(find.text('Alt Old'), findsNothing);
    expect(find.text('Geheim'), findsOneWidget);
  });

  testWidgets('books 2 crates + 3 units of a 20-crate as 43', (tester) async {
    await openDelivery(tester);
    await enter(tester, 'd1', crates: '2', units: '3');
    expect(find.text('= 43'), findsOneWidget);
    expect(find.text('Lieferung buchen (1 Getränk)'), findsOneWidget);
    await tester.tap(submit());
    await tester.pumpAndSettle();
    expect(find.text('1 Getränk, 43 Einheiten buchen?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delivery-confirm')));
    await tester.pumpAndSettle();
    final sent = items(deliveryRequests().single);
    expect(sent, hasLength(1));
    expect(sent.single['drink_id'], 'd1');
    expect(sent.single['quantity'], 43);
    expect(find.text('Lieferung gebucht'), findsOneWidget);
    expect(find.byType(DeliveryScreen), findsNothing);
  });

  testWidgets('cancelling the confirmation sends nothing', (tester) async {
    await openDelivery(tester);
    await enter(tester, 'd1', crates: '1');
    await tester.tap(submit());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delivery-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(deliveryRequests(), isEmpty);
    expect(find.byType(DeliveryScreen), findsOneWidget);
  });

  testWidgets('network failure keeps values; retry sends the same ids', (
    tester,
  ) async {
    await openDelivery(tester);
    await enter(tester, 'd1', crates: '1');
    await enter(tester, 'd2', units: '6');
    var fail = true;
    final ok = onDelivery;
    onDelivery = (r) async => fail ? throw http.ClientException('down') : ok(r);
    await book(tester);
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    expect(find.byType(DeliveryScreen), findsOneWidget);
    expect(find.text('= 20'), findsOneWidget);
    fail = false;
    await tester.pump(const Duration(seconds: 5));
    await book(tester);
    final reqs = deliveryRequests();
    expect(reqs.length, 2);
    expect(items(reqs[1]), items(reqs[0]));
    expect({for (final i in items(reqs[0])) i['id']}, hasLength(2));
    expect(find.byType(DeliveryScreen), findsNothing);
  });

  testWidgets('a rejection shows the failure toast and keeps values', (
    tester,
  ) async {
    await openDelivery(tester);
    await enter(tester, 'd1', crates: '1');
    onDelivery = (r) async => _json({'detail': 'invalid_quantity'}, 422);
    await book(tester);
    expect(find.text('Lieferung nicht möglich'), findsOneWidget);
    expect(find.byType(DeliveryScreen), findsOneWidget);
    expect(find.text('= 20'), findsOneWidget);
  });
}
