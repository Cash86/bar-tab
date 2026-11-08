import 'dart:convert';

import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/persons_screen.dart';
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

Person _person(
  String id,
  String name, {
  String tier = 't1',
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

Map<String, Object?> _dto(Person p) => {
  'id': p.id,
  'name': p.name,
  'price_tier_id': p.priceTierId,
  'is_hidden': p.isHidden,
  'is_collective': p.isCollective,
  'is_active': p.isActive,
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
  late List<Person> persons;
  late List<PriceTier> tiers;

  /// Answers person writes; default: stores the body and answers 200.
  late Future<http.Response> Function(http.Request r) onWrite;
  late ProviderContainer container;

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    tiers = const [
      PriceTier(id: 't2', name: 'Guests', sortOrder: 2),
      PriceTier(id: 't1', name: 'Members', sortOrder: 1),
    ];
    persons = [
      _person('p1', 'Kim Example'),
      _person('p2', 'Bo Sample', tier: 't2'),
      _person('p3', 'Ann Old', active: false),
      _person('p4', 'Zoe Hidden', hidden: true),
      _person('p5', 'Team Cash', collective: true),
    ];
    onWrite = (r) async {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final id = r.method == 'POST' ? 'new' : r.url.pathSegments.last;
      final p = Person(
        id: id,
        name: body['name'] as String,
        priceTierId: body['price_tier_id'] as String,
        isHidden: body['is_hidden'] as bool,
        isCollective: body['is_collective'] as bool,
        isActive: (body['is_active'] as bool?) ?? true,
      );
      persons = [
        for (final o in persons)
          if (o.id != id) o,
        p,
      ];
      container.read(_revision.notifier).state++;
      return _json(_dto(p));
    };
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (path.contains('admin/persons') && r is http.Request) {
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
    persons: persons,
    groups: const [],
    drinks: const [],
    etag: 'e',
  );

  Future<void> openPersons(WidgetTester tester) async {
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
    await tester.tap(find.byKey(const Key('admin-tile-persons')));
    await tester.pumpAndSettle();
    expect(find.byType(PersonsScreen), findsOneWidget);
  }

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

  Finder saveButton() => find.byKey(const Key('person-save'));

  Future<void> enterName(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const Key('person-name')), name);
    await tester.pump();
  }

  /// The last person write; a sync may have followed it.
  http.Request lastWrite() => server.requests
      .whereType<http.Request>()
      .lastWhere((r) => r.url.path.contains('admin/persons'));

  Map<String, dynamic> lastBody() =>
      jsonDecode(lastWrite().body) as Map<String, dynamic>;

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('lists active persons in sections, alphabetical', (tester) async {
    await openPersons(tester);
    expect(find.text('Aktiv (4)'), findsOneWidget);
    expect(find.text('Deaktiviert (1)'), findsOneWidget);
    expect(find.text('Ann Old'), findsNothing);
    final order = [
      'Sammelkonten',
      'Team Cash',
      'Members',
      'Kim Example',
      'Guests',
      'Bo Sample',
      'Versteckt',
      'Zoe Hidden',
    ];
    final ys = [for (final t in order) y(tester, t)];
    expect(ys, [...ys]..sort());
  });

  testWidgets('without price tiers "+ Neu" is disabled with a hint', (
    tester,
  ) async {
    tiers = const [];
    persons = [];
    await openPersons(tester);
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('person-new')),
    );
    expect(button.enabled, isFalse);
    expect(find.text('Zuerst eine Preisstufe anlegen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('person-new')));
    await tester.pumpAndSettle();
    expect(find.byType(PersonDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with price tiers "+ Neu" has no hint', (tester) async {
    await openPersons(tester);
    expect(find.text('Zuerst eine Preisstufe anlegen'), findsNothing);
  });

  testWidgets('the deactivated segment lists deactivated persons', (
    tester,
  ) async {
    await openPersons(tester);
    await tester.tap(find.text('Deaktiviert (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Ann Old'), findsOneWidget);
    expect(find.text('Kim Example'), findsNothing);
  });

  testWidgets('creating a person sends the trimmed name and closes', (
    tester,
  ) async {
    await openPersons(tester);
    await tester.tap(find.text('+ Neue Person'));
    await tester.pumpAndSettle();
    expect(find.text('Neue Person'), findsOneWidget);
    await enterName(tester, '  Lena New  ');
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    final r = lastWrite();
    expect(r.method, 'POST');
    expect(r.url.path, endsWith('admin/persons'));
    expect(r.headers['X-Admin-Token'], 't1');
    expect(lastBody()['name'], 'Lena New');
    expect(lastBody()['price_tier_id'], 't1');
    expect(lastBody().containsKey('is_active'), isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Lena New'), findsOneWidget);
  });

  testWidgets('a taken name is refused before anything is sent', (
    tester,
  ) async {
    await openPersons(tester);
    final before = server.requests.length;
    await tester.tap(find.text('+ Neue Person'));
    await tester.pumpAndSettle();
    await enterName(tester, ' kim example');
    expect(inDialog(find.text('Name ist schon vergeben')), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    expect(server.requests.length, before);
  });

  testWidgets('a person may keep its own name when editing', (tester) async {
    await openPersons(tester);
    await tester.tap(find.byKey(const Key('person-p1')));
    await tester.pumpAndSettle();
    expect(find.text('Person bearbeiten'), findsOneWidget);
    expect(inDialog(find.text('Name ist schon vergeben')), findsNothing);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
  });

  testWidgets('an empty name cannot be saved', (tester) async {
    await openPersons(tester);
    await tester.tap(find.text('+ Neue Person'));
    await tester.pumpAndSettle();
    await enterName(tester, '   ');
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
  });

  testWidgets('shows the character counter', (tester) async {
    await openPersons(tester);
    await tester.tap(find.text('+ Neue Person'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Twelve chars');
    expect(find.text('12/20'), findsOneWidget);
  });

  testWidgets('a server 409 keeps the dialog open with the message', (
    tester,
  ) async {
    onWrite = (r) async => _json({'detail': 'name_taken'}, 409);
    await openPersons(tester);
    await tester.tap(find.text('+ Neue Person'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Lena New');
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(inDialog(find.text('Name ist schon vergeben')), findsOneWidget);
  });

  testWidgets('an ended session leaves to the PIN prompt without popping', (
    tester,
  ) async {
    onWrite = (r) async => _json({'detail': 'admin_session_required'}, 401);
    await openPersons(tester);
    await tester.tap(find.text('+ Neue Person'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Lena New');
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PersonsScreen), findsNothing);
    expect(find.byKey(const Key('admin-pin-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('another rejection says saving is not possible', (tester) async {
    onWrite = (r) async => _json({'detail': 'unknown_reference'}, 422);
    await openPersons(tester);
    await tester.tap(find.text('+ Neue Person'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Lena New');
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Speichern nicht möglich')), findsOneWidget);
  });

  testWidgets('an unreachable server is reported in the dialog', (
    tester,
  ) async {
    onWrite = (r) async => throw http.ClientException('down');
    await openPersons(tester);
    await tester.tap(find.text('+ Neue Person'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Lena New');
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Server nicht erreichbar')), findsOneWidget);
  });

  testWidgets('deactivating moves the person to the deactivated list', (
    tester,
  ) async {
    await openPersons(tester);
    await tester.tap(find.byKey(const Key('person-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('person-toggle-active')));
    await tester.pumpAndSettle();

    final r = lastWrite();
    expect(r.method, 'PUT');
    expect(r.url.path, endsWith('admin/persons/p1'));
    expect(lastBody()['is_active'], isFalse);
    expect(lastBody()['name'], 'Kim Example');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Aktiv (3)'), findsOneWidget);
    expect(find.text('Deaktiviert (2)'), findsOneWidget);
    expect(find.text('Kim Example'), findsNothing);
  });

  testWidgets('a deactivated person can be activated again', (tester) async {
    await openPersons(tester);
    await tester.tap(find.text('Deaktiviert (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('person-p3')));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Aktivieren')), findsOneWidget);
    await tester.tap(find.byKey(const Key('person-toggle-active')));
    await tester.pumpAndSettle();
    expect(lastBody()['is_active'], isTrue);
    expect(find.text('Aktiv (5)'), findsOneWidget);
  });

  testWidgets('editing sends the changed flags and tier', (tester) async {
    await openPersons(tester);
    await tester.tap(find.byKey(const Key('person-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('person-collective')));
    await tester.tap(find.byKey(const Key('person-hidden')));
    await tester.tap(inDialog(find.text('Guests')));
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(lastBody()['is_collective'], isTrue);
    expect(lastBody()['is_hidden'], isTrue);
    expect(lastBody()['price_tier_id'], 't2');
    expect(lastBody()['is_active'], isTrue);
  });
}
