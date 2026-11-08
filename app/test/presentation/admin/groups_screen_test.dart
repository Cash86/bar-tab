import 'dart:convert';

import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/master_data.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/groups_screen.dart';
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

Drink _drink(String id, String group, {bool active = true}) => Drink(
  id: id,
  name: 'Drink $id',
  groupId: group,
  crateSize: 20,
  sortOrder: 1,
  isHidden: false,
  isActive: active,
  prices: const {'t1': 140},
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
  late List<DrinkGroup> groups;
  late List<Drink> drinks;
  late ProviderContainer container;

  late Future<http.Response> Function(http.Request r) onWrite;
  late Future<http.Response> Function(http.Request r) onOrder;

  void bump() => container.read(_revision.notifier).state++;

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    groups = const [
      DrinkGroup(id: 'g1', name: 'Bier', sortOrder: 1, color: 0xFF1275D9),
      // A colour outside the palette (e.g. set by an older version).
      DrinkGroup(id: 'g2', name: 'Softdrinks', sortOrder: 2, color: 0xFF123456),
      DrinkGroup(id: 'g3', name: 'Leer', sortOrder: 3, color: 0xFFEA1313),
    ];
    drinks = [
      _drink('d1', 'g1'),
      _drink('d2', 'g1', active: false),
      _drink('d3', 'g2'),
    ];
    onWrite = (r) async {
      final body = r.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(r.body) as Map<String, dynamic>;
      if (r.method == 'DELETE') {
        final id = r.url.pathSegments.last;
        groups = [
          for (final g in groups)
            if (g.id != id) g,
        ];
        bump();
        return http.Response('', 204);
      }
      final id = r.method == 'POST' ? 'new' : r.url.pathSegments.last;
      final hex = (body['color'] as String).substring(1);
      final g = DrinkGroup(
        id: id,
        name: body['name'] as String,
        sortOrder: 9,
        color: 0xFF000000 | int.parse(hex, radix: 16),
      );
      groups = [
        for (final o in groups)
          if (o.id != id) o,
        g,
      ];
      bump();
      return _json({
        'id': id,
        'name': g.name,
        'sort_order': 9,
        'color': body['color'],
      });
    };
    onOrder = (r) async {
      final ids = ((jsonDecode(r.body) as Map<String, dynamic>)['ids'] as List)
          .cast<String>();
      groups = [
        for (final g in groups) g.copyWith(sortOrder: ids.indexOf(g.id) + 1),
      ];
      bump();
      return http.Response('', 204);
    };
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (path.contains('admin/order/groups') && r is http.Request) {
        return onOrder(r);
      }
      if (path.contains('admin/groups') && r is http.Request) {
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
    tiers: const [PriceTier(id: 't1', name: 'Members', sortOrder: 1)],
    persons: const [],
    groups: groups,
    drinks: drinks,
    etag: 'e',
  );

  Future<void> openGroups(WidgetTester tester) async {
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
    await tester.tap(find.byKey(const Key('admin-tile-groups')));
    await tester.pumpAndSettle();
    expect(find.byType(GroupsScreen), findsOneWidget);
  }

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

  Finder saveButton() => find.byKey(const Key('group-save'));
  Finder deleteButton() => find.byKey(const Key('group-delete'));
  Finder swatch(String hex) => find.byKey(Key('group-swatch-$hex'));

  http.Request lastWrite() => server.requests
      .whereType<http.Request>()
      .lastWhere((r) => r.url.path.contains('admin/groups'));

  Map<String, dynamic> lastBody() =>
      jsonDecode(lastWrite().body) as Map<String, dynamic>;

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('lists the groups in order with dot and drink count', (
    tester,
  ) async {
    await openGroups(tester);
    final ys = [
      for (final t in ['Bier', 'Softdrinks', 'Leer']) y(tester, t),
    ];
    expect(ys, [...ys]..sort());
    // Deactivated drinks count too.
    expect(find.text('2 Getränke'), findsOneWidget);
    expect(find.text('1 Getränk'), findsOneWidget);
    expect(find.text('0 Getränke'), findsOneWidget);
    final dot = tester.widget<Container>(find.byKey(const Key('group-dot-g1')));
    expect((dot.decoration! as BoxDecoration).color, const Color(0xFF1275D9));
  });

  testWidgets('creating sends the chosen palette colour', (tester) async {
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-new')));
    await tester.pumpAndSettle();
    expect(find.text('Neue Gruppe'), findsOneWidget);
    // A new group needs a name; the first palette colour is preselected.
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('group-name')), '  Wein ');
    await tester.pump();
    await tester.tap(swatch(groupPalette[4]));
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    final r = lastWrite();
    expect(r.method, 'POST');
    expect(r.url.path, endsWith('admin/groups'));
    expect(r.headers['X-Admin-Token'], 't1');
    expect(lastBody(), {'name': 'Wein', 'color': groupPalette[4]});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Wein'), findsOneWidget);
  });

  testWidgets('a new group preselects the first palette colour', (
    tester,
  ) async {
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name')), 'Wein');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(lastBody()['color'], groupPalette.first);
  });

  testWidgets('shows the palette swatches with the stored colour selected', (
    tester,
  ) async {
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-g1')));
    await tester.pumpAndSettle();
    final swatches = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('group-swatch-'),
    );
    // Exactly the palette: no extra swatch for a palette colour.
    expect(swatches, findsNWidgets(groupPalette.length));
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      find.descendant(
        of: swatch('#1275D9'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a colour outside the palette is an extra selected swatch', (
    tester,
  ) async {
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-g2')));
    await tester.pumpAndSettle();
    expect(swatch('#123456'), findsOneWidget);
    expect(
      find.descendant(
        of: swatch('#123456'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    // Saving without touching the colour keeps it.
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(lastWrite().method, 'PUT');
    expect(lastWrite().url.path, endsWith('admin/groups/g2'));
    expect(lastBody(), {'name': 'Softdrinks', 'color': '#123456'});
  });

  testWidgets('a taken or too long name cannot be saved', (tester) async {
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name')), ' bier');
    await tester.pump();
    expect(inDialog(find.text('Name ist schon vergeben')), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('group-name')), 'a' * 17);
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('group-name')));
    expect(field.controller!.text, 'a' * 16);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
  });

  testWidgets('deleting is disabled while the group has drinks', (
    tester,
  ) async {
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-g1')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);
    expect(inDialog(find.text('Gruppe enthält noch Getränke')), findsOneWidget);
  });

  testWidgets('an empty group is deleted after confirmation', (tester) async {
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-g3')));
    await tester.pumpAndSettle();
    expect(find.text('Gruppe enthält noch Getränke'), findsNothing);
    final before = server.requests.length;
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(find.text('Gruppe „Leer“ löschen?'), findsOneWidget);
    expect(server.requests.length, before);
    await tester.tap(find.byKey(const Key('group-delete-confirm')));
    await tester.pumpAndSettle();
    expect(lastWrite().method, 'DELETE');
    expect(lastWrite().url.path, endsWith('admin/groups/g3'));
    expect(lastWrite().headers['X-Admin-Token'], 't1');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Leer'), findsNothing);
  });

  testWidgets('cancelling the confirmation deletes nothing', (tester) async {
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-g3')));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-delete-cancel')));
    await tester.pumpAndSettle();
    expect(
      server.requests.whereType<http.Request>().where(
        (r) => r.method == 'DELETE',
      ),
      isEmpty,
    );
    // The edit dialog is still open.
    expect(find.byKey(const Key('group-name')), findsOneWidget);
  });

  testWidgets('409 group_in_use says deleting is not possible and reloads', (
    tester,
  ) async {
    onWrite = (r) async {
      // A drink was moved into the group meanwhile.
      drinks = [...drinks, _drink('d9', 'g3')];
      return _json({'detail': 'group_in_use'}, 409);
    };
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-g3')));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(inDialog(find.text('Löschen nicht möglich')), findsOneWidget);
    // The reloaded catalog now disables the button.
    expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);
    expect(find.text('1 Getränk'), findsNWidgets(2));
  });

  testWidgets('a server 409 name_taken keeps the dialog open', (tester) async {
    onWrite = (r) async => _json({'detail': 'name_taken'}, 409);
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-g3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name')), 'Anders');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Name ist schon vergeben')), findsOneWidget);
  });

  testWidgets('an ended session on save leaves to the PIN prompt', (
    tester,
  ) async {
    onWrite = (r) async => _json({'detail': 'admin_session_required'}, 401);
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-g3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name')), 'Anders');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(GroupsScreen), findsNothing);
    expect(find.byKey(const Key('admin-pin-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an ended session on delete leaves without double pop', (
    tester,
  ) async {
    onWrite = (r) async => _json({'detail': 'admin_session_required'}, 401);
    await openGroups(tester);
    await tester.tap(find.byKey(const Key('group-g3')));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(GroupsScreen), findsNothing);
    expect(find.byKey(const Key('admin-pin-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('reorder', () {
    Future<void> dragDown(WidgetTester tester, String id, double dy) async {
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(Key('group-handle-$id'))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
    }

    testWidgets('sends the full id list in the new order', (tester) async {
      await openGroups(tester);
      await dragDown(tester, 'g1', 90);
      await tester.pumpAndSettle();
      final r = server.requests.whereType<http.Request>().lastWhere(
        (r) => r.url.path.contains('admin/order/groups'),
      );
      expect(r.method, 'PUT');
      expect((jsonDecode(r.body) as Map<String, dynamic>)['ids'], [
        'g2',
        'g1',
        'g3',
      ]);
      expect(y(tester, 'Softdrinks'), lessThan(y(tester, 'Bier')));
    });

    testWidgets('a failed reorder reverts and says saving failed', (
      tester,
    ) async {
      onOrder = (r) async => _json({'detail': 'order_mismatch'}, 409);
      await openGroups(tester);
      await dragDown(tester, 'g1', 90);
      await tester.pumpAndSettle();
      expect(find.text('Speichern nicht möglich'), findsOneWidget);
      expect(y(tester, 'Bier'), lessThan(y(tester, 'Softdrinks')));
    });

    testWidgets('a rejected reorder reloads the catalog for the next try', (
      tester,
    ) async {
      onOrder = (r) async {
        // Another tablet added a group meanwhile: the order no longer
        // matches. No revision bump, so only a reload shows it.
        groups = [
          ...groups,
          const DrinkGroup(
            id: 'g9',
            name: 'Wein',
            sortOrder: 9,
            color: 0xFF123456,
          ),
        ];
        return _json({'detail': 'order_mismatch'}, 409);
      };
      await openGroups(tester);
      await dragDown(tester, 'g1', 90);
      await tester.pumpAndSettle();
      expect(find.text('Speichern nicht möglich'), findsOneWidget);
      expect(find.text('Wein'), findsOneWidget);
    });
  });
}
