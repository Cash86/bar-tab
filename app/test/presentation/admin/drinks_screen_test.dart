import 'dart:convert';

import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/drinks_screen.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../fixtures/fakes.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Drink _drink(
  String id,
  String name, {
  String group = 'g1',
  int crate = 20,
  int order = 1,
  bool hidden = false,
  bool active = true,
  Map<String, int> prices = const {'t1': 140, 't2': 180},
}) => Drink(
  id: id,
  name: name,
  groupId: group,
  crateSize: crate,
  sortOrder: order,
  isHidden: hidden,
  isActive: active,
  prices: prices,
);

Map<String, Object?> _dto(Drink d) => {
  'id': d.id,
  'name': d.name,
  'group_id': d.groupId,
  'crate_size': d.crateSize,
  'sort_order': d.sortOrder,
  'is_hidden': d.isHidden,
  'is_active': d.isActive,
  'prices': d.prices,
};

class _NoCatalog implements CatalogRepository {
  @override
  Future<Catalog?> cached() async => null;

  @override
  Future<void> save(Catalog catalog) async {}

  @override
  Future<void> clear() async {}
}

/// Bumped by the fake server after a write, standing in for the sync.
final _revision = StateProvider<int>((ref) => 0);

void main() {
  late FakeApiServer server;
  late FixedClock clock;
  late List<Drink> drinks;
  late List<PriceTier> tiers;
  late ProviderContainer container;

  /// Answers drink writes; default: stores the body and answers 200.
  late Future<http.Response> Function(http.Request r) onWrite;

  /// Answers reorder requests; default: stores the order and answers 204.
  late Future<http.Response> Function(http.Request r) onOrder;

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    tiers = const [
      PriceTier(id: 't2', name: 'Guests', sortOrder: 2),
      PriceTier(id: 't1', name: 'Members', sortOrder: 1),
    ];
    drinks = [
      _drink('d1', 'Pils'),
      _drink('d2', 'Weizen', order: 2, crate: 24),
      _drink('d3', 'Alt Old', order: 3, active: false),
      _drink('d4', 'Cola', group: 'g2', crate: 12),
    ];
    onWrite = (r) async {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final id = r.method == 'POST' ? 'new' : r.url.pathSegments.last;
      final d = Drink(
        id: id,
        name: body['name'] as String,
        groupId: body['group_id'] as String,
        crateSize: body['crate_size'] as int,
        sortOrder: 9,
        isHidden: body['is_hidden'] as bool,
        isActive: (body['is_active'] as bool?) ?? true,
        prices: (body['prices'] as Map<String, dynamic>).cast<String, int>(),
      );
      drinks = [
        for (final o in drinks)
          if (o.id != id) o,
        d,
      ];
      container.read(_revision.notifier).state++;
      return _json(_dto(d));
    };
    onOrder = (r) async {
      final ids = ((jsonDecode(r.body) as Map<String, dynamic>)['ids'] as List)
          .cast<String>();
      drinks = [
        for (final d in drinks)
          if (ids.contains(d.id))
            d.copyWith(sortOrder: ids.indexOf(d.id) + 1)
          else
            d,
      ];
      container.read(_revision.notifier).state++;
      return http.Response('', 204);
    };
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (path.contains('admin/order/drinks') && r is http.Request) {
        return onOrder(r);
      }
      if (path.contains('admin/drinks') && r is http.Request) {
        return onWrite(r);
      }
      // The sync after a write finds nothing to do.
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

  Catalog catalog() => Catalog(
    tiers: tiers,
    persons: const [],
    groups: const [
      DrinkGroup(id: 'g2', name: 'Softdrinks', sortOrder: 2, color: 0xFF2196F3),
      DrinkGroup(id: 'g1', name: 'Bier', sortOrder: 1, color: 0xFFFFC107),
    ],
    drinks: drinks,
    etag: 'e',
  );

  Future<void> openDrinks(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(pairedStore()),
          httpClientProvider.overrideWithValue(server.client),
          clockProvider.overrideWithValue(clock),
          catalogProvider.overrideWith((ref) async {
            ref.watch(_revision);
            return catalog();
          }),
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
    container = ProviderScope.containerOf(
      tester.element(find.byType(NameListScreen)),
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
    await tester.tap(find.byKey(const Key('admin-tile-drinks')));
    await tester.pumpAndSettle();
    expect(find.byType(DrinksScreen), findsOneWidget);
  }

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

  Finder saveButton() => find.byKey(const Key('drink-save'));

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.pump();
  }

  Future<void> fillNew(WidgetTester tester) async {
    await tester.tap(find.text('+ Neues Getränk'));
    await tester.pumpAndSettle();
    await enter(tester, 'drink-name', '  Radler ');
    await enter(tester, 'drink-crate', '10');
    await enter(tester, 'drink-price-t1', '1,2');
    await enter(tester, 'drink-price-t2', '1.50');
  }

  http.Request lastWrite() => server.requests
      .whereType<http.Request>()
      .lastWhere((r) => r.url.path.contains('admin/drinks'));

  Map<String, dynamic> lastBody() =>
      jsonDecode(lastWrite().body) as Map<String, dynamic>;

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  const nb = ' ';

  testWidgets('lists active drinks per group with crate and prices', (
    tester,
  ) async {
    await openDrinks(tester);
    expect(find.text('Aktiv (3)'), findsOneWidget);
    expect(find.text('Deaktiviert (1)'), findsOneWidget);
    expect(find.text('Alt Old'), findsNothing);
    expect(find.text('Kasten 20 · 1,40$nb€ / 1,80$nb€'), findsOneWidget);
    final order = ['Bier', 'Pils', 'Weizen', 'Softdrinks', 'Cola'];
    final ys = [for (final t in order) y(tester, t)];
    expect(ys, [...ys]..sort());
  });

  testWidgets('the deactivated segment lists deactivated drinks', (
    tester,
  ) async {
    await openDrinks(tester);
    await tester.tap(find.text('Deaktiviert (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Alt Old'), findsOneWidget);
    expect(find.text('Pils'), findsNothing);
  });

  testWidgets('creating sends prices keyed by tier id in cents', (
    tester,
  ) async {
    await openDrinks(tester);
    await fillNew(tester);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    final r = lastWrite();
    expect(r.method, 'POST');
    expect(r.url.path, endsWith('admin/drinks'));
    expect(r.headers['X-Admin-Token'], 't1');
    expect(lastBody()['name'], 'Radler');
    expect(lastBody()['group_id'], 'g1');
    expect(lastBody()['crate_size'], 10);
    expect(lastBody()['is_hidden'], isFalse);
    expect(lastBody()['prices'], {'t1': 120, 't2': 150});
    expect(lastBody().containsKey('is_active'), isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Radler'), findsOneWidget);
  });

  testWidgets('the group and the hidden flag are sent', (tester) async {
    await openDrinks(tester);
    await fillNew(tester);
    await tester.tap(find.byKey(const Key('drink-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Softdrinks').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drink-hidden')));
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(lastBody()['group_id'], 'g2');
    expect(lastBody()['is_hidden'], isTrue);
  });

  testWidgets('saving without a price for one tier is disabled', (
    tester,
  ) async {
    await openDrinks(tester);
    await fillNew(tester);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
    await enter(tester, 'drink-price-t2', '');
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await enter(tester, 'drink-price-t2', '1,505');
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
  });

  testWidgets('a crate size below 1 cannot be saved', (tester) async {
    await openDrinks(tester);
    await fillNew(tester);
    await enter(tester, 'drink-crate', '0');
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await enter(tester, 'drink-crate', '');
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
  });

  testWidgets('a taken name is refused before anything is sent', (
    tester,
  ) async {
    await openDrinks(tester);
    final before = server.requests.length;
    await fillNew(tester);
    await enter(tester, 'drink-name', ' pils');
    expect(inDialog(find.text('Name ist schon vergeben')), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    expect(server.requests.length, before);
  });

  testWidgets('a deactivated drink name is taken too', (tester) async {
    await openDrinks(tester);
    await fillNew(tester);
    await enter(tester, 'drink-name', 'alt old');
    expect(inDialog(find.text('Name ist schon vergeben')), findsOneWidget);
  });

  testWidgets('editing shows the stored values and keeps the own name', (
    tester,
  ) async {
    await openDrinks(tester);
    await tester.tap(find.byKey(const Key('drink-d2')));
    await tester.pumpAndSettle();
    expect(find.text('Getränk bearbeiten'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Weizen'), findsOneWidget);
    expect(find.widgetWithText(TextField, '24'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1,40'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1,80'), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
    await enter(tester, 'drink-price-t1', '1,60');
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(lastWrite().method, 'PUT');
    expect(lastWrite().url.path, endsWith('admin/drinks/d2'));
    expect(lastBody()['prices'], {'t1': 160, 't2': 180});
    expect(lastBody()['is_active'], isTrue);
  });

  testWidgets('deactivating saves at once', (tester) async {
    await openDrinks(tester);
    await tester.tap(find.byKey(const Key('drink-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drink-toggle-active')));
    await tester.pumpAndSettle();
    expect(lastWrite().url.path, endsWith('admin/drinks/d1'));
    expect(lastBody()['is_active'], isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Aktiv (2)'), findsOneWidget);
    expect(find.text('Deaktiviert (2)'), findsOneWidget);
  });

  testWidgets('a deactivated drink can be activated again', (tester) async {
    await openDrinks(tester);
    await tester.tap(find.text('Deaktiviert (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drink-d3')));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Aktivieren')), findsOneWidget);
    await tester.tap(find.byKey(const Key('drink-toggle-active')));
    await tester.pumpAndSettle();
    expect(lastBody()['is_active'], isTrue);
    expect(find.text('Aktiv (4)'), findsOneWidget);
  });

  testWidgets('a server 409 keeps the dialog open with the message', (
    tester,
  ) async {
    onWrite = (r) async => _json({'detail': 'name_taken'}, 409);
    await openDrinks(tester);
    await fillNew(tester);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(inDialog(find.text('Name ist schon vergeben')), findsOneWidget);
  });

  testWidgets('another rejection says saving is not possible', (tester) async {
    onWrite = (r) async => _json({'detail': 'unknown_reference'}, 422);
    await openDrinks(tester);
    await fillNew(tester);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Speichern nicht möglich')), findsOneWidget);
  });

  testWidgets('an ended session leaves to the PIN prompt without popping', (
    tester,
  ) async {
    onWrite = (r) async => _json({'detail': 'admin_session_required'}, 401);
    await openDrinks(tester);
    await fillNew(tester);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(DrinksScreen), findsNothing);
    expect(find.byKey(const Key('admin-pin-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prices_incomplete keeps the values and reloads the catalog', (
    tester,
  ) async {
    // A tier was added meanwhile: the write is refused, the catalog now
    // contains the new tier.
    final accept = onWrite;
    onWrite = (r) async {
      onWrite = accept;
      tiers = [...tiers, const PriceTier(id: 't3', name: 'VIPs', sortOrder: 3)];
      container.read(_revision.notifier).state++;
      return _json({'detail': 'prices_incomplete'}, 422);
    };
    await openDrinks(tester);
    await fillNew(tester);
    expect(find.byKey(const Key('drink-price-t3')), findsNothing);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      inDialog(
        find.text('Preise passen nicht mehr zu den Preisstufen – bitte prüfen'),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, '  Radler '), findsOneWidget);
    expect(find.widgetWithText(TextField, '1,2'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1.50'), findsOneWidget);
    final t3 = find.byKey(const Key('drink-price-t3'));
    expect(t3, findsOneWidget);
    expect(tester.widget<TextField>(t3).controller!.text, isEmpty);
    // The new tier needs a price before saving again.
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await enter(tester, 'drink-price-t3', '2');
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(lastBody()['prices'], {'t1': 120, 't2': 150, 't3': 200});
  });

  group('reorder', () {
    Future<void> dragDown(WidgetTester tester, String id, double dy) async {
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(Key('drink-handle-$id'))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
    }

    Map<String, dynamic> orderBody() {
      final r = server.requests.whereType<http.Request>().lastWhere(
        (r) => r.url.path.contains('admin/order/drinks'),
      );
      return jsonDecode(r.body) as Map<String, dynamic>;
    }

    testWidgets('sends all drink ids of the group in the new order', (
      tester,
    ) async {
      await openDrinks(tester);
      await dragDown(tester, 'd1', 90);
      await tester.pumpAndSettle();
      final r = server.requests.whereType<http.Request>().lastWhere(
        (r) => r.url.path.contains('admin/order/drinks'),
      );
      expect(r.method, 'PUT');
      expect(r.url.path, endsWith('admin/order/drinks/g1'));
      // Deactivated d3 keeps its place at the end.
      expect(orderBody()['ids'], ['d2', 'd1', 'd3']);
      expect(y(tester, 'Weizen'), lessThan(y(tester, 'Pils')));
    });

    testWidgets('a failed reorder reverts and says saving failed', (
      tester,
    ) async {
      onOrder = (r) async => _json({'detail': 'order_mismatch'}, 409);
      await openDrinks(tester);
      await dragDown(tester, 'd1', 90);
      await tester.pumpAndSettle();
      expect(find.text('Speichern nicht möglich'), findsOneWidget);
      expect(y(tester, 'Pils'), lessThan(y(tester, 'Weizen')));
    });
  });
}
