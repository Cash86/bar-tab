import 'dart:convert';

import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/tiers_screen.dart';
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

Person _person(String id, String tier, {bool active = true}) => Person(
  id: id,
  name: 'Person $id',
  priceTierId: tier,
  isHidden: false,
  isCollective: false,
  isActive: active,
);

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
  late List<PriceTier> tiers;
  late List<Person> persons;
  late ProviderContainer container;

  late Future<http.Response> Function(http.Request r) onWrite;
  late Future<http.Response> Function(http.Request r) onOrder;

  void bump() => container.read(_revision.notifier).state++;

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    tiers = const [
      PriceTier(id: 't1', name: 'Aktive', sortOrder: 1),
      PriceTier(id: 't2', name: 'AH', sortOrder: 2),
      PriceTier(id: 't3', name: 'Gäste', sortOrder: 3),
    ];
    persons = [
      _person('p1', 't1'),
      _person('p2', 't1', active: false),
      _person('p3', 't2'),
    ];
    onWrite = (r) async {
      if (r.method == 'DELETE') {
        final id = r.url.pathSegments.last;
        tiers = [
          for (final t in tiers)
            if (t.id != id) t,
        ];
        bump();
        return http.Response('', 204);
      }
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final id = r.method == 'POST' ? 'new' : r.url.pathSegments.last;
      final t = PriceTier(id: id, name: body['name'] as String, sortOrder: 9);
      tiers = [
        for (final o in tiers)
          if (o.id != id) o,
        t,
      ];
      bump();
      return _json({'id': id, 'name': t.name, 'sort_order': 9});
    };
    onOrder = (r) async {
      final ids = ((jsonDecode(r.body) as Map<String, dynamic>)['ids'] as List)
          .cast<String>();
      tiers = [
        for (final t in tiers) t.copyWith(sortOrder: ids.indexOf(t.id) + 1),
      ];
      bump();
      return http.Response('', 204);
    };
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (path.contains('admin/order/price-tiers') && r is http.Request) {
        return onOrder(r);
      }
      if (path.contains('admin/price-tiers') && r is http.Request) {
        return onWrite(r);
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

  Catalog catalog() => Catalog(
    tiers: tiers,
    persons: persons,
    groups: const [],
    drinks: const [],
    etag: 'e',
  );

  Future<void> openTiers(WidgetTester tester) async {
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
    await tester.tap(find.byKey(const Key('admin-tile-tiers')));
    await tester.pumpAndSettle();
    expect(find.byType(TiersScreen), findsOneWidget);
  }

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

  Finder saveButton() => find.byKey(const Key('tier-save'));
  Finder deleteButton() => find.byKey(const Key('tier-delete'));

  http.Request lastWrite() => server.requests
      .whereType<http.Request>()
      .lastWhere((r) => r.url.path.contains('admin/price-tiers'));

  Map<String, dynamic> lastBody() =>
      jsonDecode(lastWrite().body) as Map<String, dynamic>;

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('lists the tiers in order with person count', (tester) async {
    await openTiers(tester);
    final ys = [
      for (final t in ['Aktive', 'AH', 'Gäste']) y(tester, t),
    ];
    expect(ys, [...ys]..sort());
    // Deactivated persons count too.
    expect(find.text('2 Personen'), findsOneWidget);
    expect(find.text('1 Person'), findsOneWidget);
    expect(find.text('0 Personen'), findsOneWidget);
  });

  testWidgets('creating sends the name and states where prices come from', (
    tester,
  ) async {
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-new')));
    await tester.pumpAndSettle();
    expect(find.text('Neue Preisstufe'), findsOneWidget);
    expect(
      inDialog(find.text('Preise werden von Aktive übernommen')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('tier-name')), '  VIP ');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    final r = lastWrite();
    expect(r.method, 'POST');
    expect(r.url.path, endsWith('admin/price-tiers'));
    expect(r.headers['X-Admin-Token'], 't1');
    expect(lastBody(), {'name': 'VIP'});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('VIP'), findsOneWidget);
  });

  testWidgets('editing renames and shows no copy hint', (tester) async {
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-t2')));
    await tester.pumpAndSettle();
    expect(find.text('Preisstufe bearbeiten'), findsOneWidget);
    expect(find.textContaining('übernommen'), findsNothing);
    await tester.enterText(find.byKey(const Key('tier-name')), 'Alte Herren');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(lastWrite().method, 'PUT');
    expect(lastWrite().url.path, endsWith('admin/price-tiers/t2'));
    expect(lastBody(), {'name': 'Alte Herren'});
  });

  testWidgets('a taken or too long name cannot be saved', (tester) async {
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tier-name')), ' ah');
    await tester.pump();
    expect(inDialog(find.text('Name ist schon vergeben')), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('tier-name')), 'a' * 17);
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('tier-name')));
    expect(field.controller!.text, 'a' * 16);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
  });

  testWidgets('deleting is disabled while persons use the tier', (
    tester,
  ) async {
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-t1')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);
    expect(
      inDialog(find.text('Preisstufe wird noch verwendet')),
      findsOneWidget,
    );
  });

  testWidgets('the last tier cannot be deleted', (tester) async {
    tiers = const [PriceTier(id: 't3', name: 'Gäste', sortOrder: 1)];
    persons = const [];
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-t3')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);
    expect(
      inDialog(find.text('Die letzte Preisstufe kann nicht gelöscht werden')),
      findsOneWidget,
    );
  });

  testWidgets('an unused tier is deleted after confirmation', (tester) async {
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-t3')));
    await tester.pumpAndSettle();
    final before = server.requests.length;
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(find.text('Preisstufe „Gäste“ löschen?'), findsOneWidget);
    expect(server.requests.length, before);
    await tester.tap(find.byKey(const Key('tier-delete-confirm')));
    await tester.pumpAndSettle();
    expect(lastWrite().method, 'DELETE');
    expect(lastWrite().url.path, endsWith('admin/price-tiers/t3'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Gäste'), findsNothing);
  });

  testWidgets('409 tier_in_use says deleting is not possible and reloads', (
    tester,
  ) async {
    onWrite = (r) async {
      persons = [...persons, _person('p9', 't3')];
      return _json({'detail': 'tier_in_use'}, 409);
    };
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-t3')));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tier-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(inDialog(find.text('Löschen nicht möglich')), findsOneWidget);
    expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);
  });

  testWidgets('409 last_tier says deleting is not possible', (tester) async {
    onWrite = (r) async => _json({'detail': 'last_tier'}, 409);
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-t3')));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tier-delete-confirm')));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Löschen nicht möglich')), findsOneWidget);
  });

  testWidgets('an ended session on save leaves to the PIN prompt', (
    tester,
  ) async {
    onWrite = (r) async => _json({'detail': 'admin_session_required'}, 401);
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-t3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tier-name')), 'Anders');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TiersScreen), findsNothing);
    expect(find.byKey(const Key('admin-pin-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an ended session on delete leaves without double pop', (
    tester,
  ) async {
    onWrite = (r) async => _json({'detail': 'admin_session_required'}, 401);
    await openTiers(tester);
    await tester.tap(find.byKey(const Key('tier-t3')));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tier-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TiersScreen), findsNothing);
    expect(find.byKey(const Key('admin-pin-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('reorder', () {
    Future<void> dragDown(WidgetTester tester, String id, double dy) async {
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(Key('tier-handle-$id'))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
    }

    testWidgets('sends the full id list in the new order', (tester) async {
      await openTiers(tester);
      await dragDown(tester, 't1', 90);
      await tester.pumpAndSettle();
      final r = server.requests.whereType<http.Request>().lastWhere(
        (r) => r.url.path.contains('admin/order/price-tiers'),
      );
      expect(r.method, 'PUT');
      expect((jsonDecode(r.body) as Map<String, dynamic>)['ids'], [
        't2',
        't1',
        't3',
      ]);
      expect(y(tester, 'AH'), lessThan(y(tester, 'Aktive')));
    });

    testWidgets('a failed reorder reverts and says saving failed', (
      tester,
    ) async {
      onOrder = (r) async => _json({'detail': 'order_mismatch'}, 409);
      await openTiers(tester);
      await dragDown(tester, 't1', 90);
      await tester.pumpAndSettle();
      expect(find.text('Speichern nicht möglich'), findsOneWidget);
      expect(y(tester, 'Aktive'), lessThan(y(tester, 'AH')));
    });

    testWidgets('a rejected reorder reloads the catalog for the next try', (
      tester,
    ) async {
      onOrder = (r) async {
        // Another tablet added a tier meanwhile: the order no longer
        // matches. No revision bump, so only a reload shows it.
        tiers = [
          ...tiers,
          const PriceTier(id: 't9', name: 'Ehrengast', sortOrder: 9),
        ];
        return _json({'detail': 'order_mismatch'}, 409);
      };
      await openTiers(tester);
      await dragDown(tester, 't1', 90);
      await tester.pumpAndSettle();
      expect(find.text('Speichern nicht möglich'), findsOneWidget);
      expect(find.text('Ehrengast'), findsOneWidget);
    });
  });
}
