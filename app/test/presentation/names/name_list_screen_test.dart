import 'dart:async';

import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/drinks/drink_selection_screen.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/names/name_tile.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _tiers = [
  PriceTier(id: 't1', name: 'Members', sortOrder: 1),
  PriceTier(id: 't2', name: 'Guests', sortOrder: 2),
];

Person person(
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

/// Names sort alphabetically by zero-padded index: "Name 00", "Name 01", ...
List<Person> many(int n, {String tier = 't1'}) => [
  for (var i = 0; i < n; i++)
    person('$tier-$i', 'Name ${i.toString().padLeft(2, '0')}', tier: tier),
];

Catalog catalogOf(List<Person> persons) => Catalog(
  tiers: _tiers,
  persons: persons,
  groups: const [],
  drinks: const [],
  etag: 'e',
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    Catalog? catalog, {
    Future<Catalog?>? loading,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith(
            (ref) => loading ?? Future.value(catalog),
          ),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
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
    if (loading == null) await tester.pumpAndSettle();
  }

  group('chooseLayout', () {
    const roomy = NameGridLayout(perRow: 3, tileHeight: 64, scrolls: false);
    const compact = NameGridLayout(perRow: 4, tileHeight: 52, scrolls: false);
    const scrolling = NameGridLayout(perRow: 4, tileHeight: 52, scrolls: true);
    // 3 per row @ 64: rows*64 + (rows-1)*8. 4 per row @ 52: rows*52+(rows-1)*8.
    final table = <(int, double, NameGridLayout)>[
      (0, 0, roomy),
      (12, 280, roomy), // 4 rows -> 280 exactly
      (12, 279, compact), // 3 rows @ 52 -> 172
      (30, 500, compact), // 10 rows @64 = 712 no; 8 rows @52 = 472 yes
      (30, 471, scrolling),
      (60, 500, scrolling),
    ];
    for (final (n, h, expected) in table) {
      test('$n names in $h px -> $expected', () {
        expect(chooseLayout(maxNamesInColumn: n, availableHeight: h), expected);
      });
    }
  });

  testWidgets('shows collective row and tier columns with visible names', (
    tester,
  ) async {
    await pump(
      tester,
      catalogOf([
        person('c1', 'Team Bar', collective: true),
        person('c2', 'Hidden Team', collective: true, hidden: true),
        person('a', 'Berta', tier: 't1'),
        person('b', 'Anton', tier: 't1'),
        person('g', 'Gast', tier: 't2'),
        person('h', 'Versteckt', tier: 't1', hidden: true),
        person('i', 'Inaktiv', tier: 't2', active: false),
      ]),
    );
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.text('SAMMELKONTEN'), findsOneWidget);
    expect(find.text('Team Bar'), findsOneWidget);
    expect(find.text('MEMBERS'), findsOneWidget);
    expect(find.text('GUESTS'), findsOneWidget);
    expect(find.text('Hidden Team'), findsNothing);
    expect(find.text('Versteckt'), findsNothing);
    expect(find.text('Inaktiv'), findsNothing);
    // Tier order left to right, alphabetical within a tier.
    expect(
      tester.getTopLeft(find.text('MEMBERS')).dx,
      lessThan(tester.getTopLeft(find.text('GUESTS')).dx),
    );
    expect(
      tester.getTopLeft(find.text('Anton')).dx,
      lessThan(tester.getTopLeft(find.text('Berta')).dx),
    );
    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('12 persons per tier: 3 per row, no scrolling', (tester) async {
    await pump(tester, catalogOf([...many(12), ...many(12, tier: 't2')]));
    expect(find.byType(Scrollable), findsNothing);
    final tops = [
      for (var i = 0; i < 4; i++)
        tester.getTopLeft(find.text('Name 0$i').first).dy,
    ];
    expect(tops[0], tops[1]);
    expect(tops[1], tops[2]);
    expect(tops[3], greaterThan(tops[2]));
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('Name 00').first,
                  matching: find.byType(SizedBox),
                )
                .first,
          )
          .height,
      64,
    );
  });

  testWidgets('30 persons in one tier: 4 per row at 52, no scrolling', (
    tester,
  ) async {
    await pump(tester, catalogOf(many(30)));
    expect(find.byType(Scrollable), findsNothing);
    final tops = [
      for (var i = 0; i < 5; i++) tester.getTopLeft(find.text('Name 0$i')).dy,
    ];
    expect(tops[0], tops[3]);
    expect(tops[4], greaterThan(tops[3]));
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('Name 00'),
                  matching: find.byType(SizedBox),
                )
                .first,
          )
          .height,
      52,
    );
    expect(find.text('Name 29'), findsOneWidget);
  });

  testWidgets('60 persons: column scrolls, collective row stays put', (
    tester,
  ) async {
    await pump(
      tester,
      catalogOf([person('c1', 'Team Bar', collective: true), ...many(60)]),
    );
    final before = tester.getTopLeft(find.text('Team Bar'));
    expect(find.byType(Scrollable), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Name 59'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Name 59'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Team Bar')), before);
  });

  testWidgets('tapping a name opens drink selection for that person', (
    tester,
  ) async {
    await pump(
      tester,
      catalogOf([person('p-anton', 'Anton'), person('p-berta', 'Berta')]),
    );
    await tester.tap(find.text('Berta'));
    await tester.pumpAndSettle();
    final screen = tester.widget<DrinkSelectionScreen>(
      find.byType(DrinkSelectionScreen),
    );
    expect(screen.personId, 'p-berta');
  });

  testWidgets('empty catalog shows the hint', (tester) async {
    await pump(tester, catalogOf([person('h', 'Versteckt', hidden: true)]));
    expect(
      find.text(
        'Noch keine Personen angelegt – bitte im Admin-Bereich anlegen.',
      ),
      findsOneWidget,
    );
    expect(find.text('Wer trinkt?'), findsOneWidget);
  });

  testWidgets('shows the sync indicator bottom right', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) async => catalogOf(many(3))),
          syncStateProvider.overrideWith(
            (ref) => Stream.value(
              const SyncState(
                queued: 2,
                failed: 0,
                isUnauthorised: false,
                isOffline: true,
              ),
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
    final pos = tester.getBottomRight(find.text('2 Buchungen warten'));
    expect(pos.dx, greaterThan(1000));
    expect(pos.dy, greaterThan(700));
  });

  testWidgets('tier colour follows the position among all tiers', (
    tester,
  ) async {
    // Middle tier has no visible persons and is not displayed.
    await pump(
      tester,
      Catalog(
        tiers: const [
          PriceTier(id: 't3', name: 'Third', sortOrder: 3),
          PriceTier(id: 't1', name: 'First', sortOrder: 1),
          PriceTier(id: 't2', name: 'Second', sortOrder: 2),
        ],
        persons: [
          person('a', 'Anton', tier: 't1'),
          person('c', 'Cleo', tier: 't3'),
        ],
        groups: const [],
        drinks: const [],
        etag: 'e',
      ),
    );
    expect(find.text('SECOND'), findsNothing);
    Color? titleColor(String text) =>
        tester.widget<Text>(find.text(text)).style!.color;
    expect(titleColor('FIRST'), BarTabTheme.tierColor(0));
    expect(titleColor('THIRD'), BarTabTheme.tierColor(2));
    final cleo = tester.widget<NameTile>(
      find.ancestor(of: find.text('Cleo'), matching: find.byType(NameTile)),
    );
    expect(cleo.accent, BarTabTheme.tierColor(2));
  });

  testWidgets('no empty hint while the catalog is loading', (tester) async {
    final completer = Completer<Catalog?>();
    await pump(tester, null, loading: completer.future);
    await tester.pump();
    expect(
      find.text(
        'Noch keine Personen angelegt – bitte im Admin-Bereich anlegen.',
      ),
      findsNothing,
    );
    expect(find.text('Wer trinkt?'), findsOneWidget);
  });
}
