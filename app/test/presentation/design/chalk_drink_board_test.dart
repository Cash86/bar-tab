import 'dart:math' as math;

import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/design/chalk/chalk_drink_board.dart';
import 'package:bar_tab/presentation/design/chalk_plan.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/drink_board_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _nbsp = '\u00a0';
const thirtyChars = 'Schwarzwaldkirschwasserbrandls';

Drink drink(String id, String name, String group, int sort) => Drink(
  id: id,
  name: name,
  groupId: group,
  crateSize: 20,
  sortOrder: sort,
  isHidden: false,
  isActive: true,
  prices: const {'t1': 115},
);

DrinkGroup group(String id, String name, int sort) =>
    DrinkGroup(id: id, name: name, sortOrder: sort, color: 0xFFE3A33A);

/// Bier 5, Alkoholfrei 3, Limo & Saft 11, Wasser 1 (the approved mockup).
List<(DrinkGroup, List<Drink>)> realAssortment() => [
  (
    group('g1', 'Bier', 1),
    [
      for (var i = 0; i < 5; i++)
        drink('b$i', i == 0 ? 'Pils' : 'Bier $i', 'g1', i),
    ],
  ),
  (
    group('g2', 'Alkoholfrei', 2),
    [for (var i = 0; i < 3; i++) drink('a$i', 'Frei $i', 'g2', i)],
  ),
  (
    group('g3', 'Limo & Saft', 3),
    [for (var i = 0; i < 11; i++) drink('l$i', 'Limo $i', 'g3', i)],
  ),
  (group('g4', 'Wasser', 4), [drink('w0', 'Wasser', 'g4', 0)]),
];

/// The real names of the approved mockup, [5, 3, 11, 1].
List<(DrinkGroup, List<Drink>)> realNames() {
  const names = [
    [
      'Ötti Hell',
      'Ötti Weizen',
      'Alpi klein',
      'Alpi Spezial',
      'Augustiner Hell',
    ],
    ['Krombacher alkoholfrei', 'Erdinger alkoholfrei', 'Jever Fun'],
    [
      'Colamix',
      'Colamix Zero',
      'Cola-Orange',
      'Limo Zitrone',
      'Limo Orange',
      'Eistee Zitrone',
      'Eistee Pfirsich',
      'ACE',
      'Apfelschorle',
      'Apfelkirsch',
      'Iso',
    ],
    ['Mineralwasser'],
  ];
  const groups = ['Bier', 'Alkoholfrei', 'Limo & Saft', 'Wasser'];
  return [
    for (var g = 0; g < 4; g++)
      (
        group('g$g', groups[g], g),
        [
          for (var i = 0; i < names[g].length; i++)
            drink('n$g-$i', names[g][i], 'g$g', i),
        ],
      ),
  ];
}

class Taps {
  final grid = <String>[];
  final favourites = <String>[];
}

DrinkBoardData data({
  required List<(DrinkGroup, List<Drink>)> groups,
  List<Drink> favourites = const [],
  Map<String, int> quantities = const {},
  bool enabled = true,
  bool dimmed = false,
  Taps? taps,
}) => DrinkBoardData(
  groups: groups,
  priceOf: (d) => 100 + d.sortOrder,
  colorOf: (d) => const Color(0xFFE3A33A),
  quantities: quantities,
  favourites: favourites,
  favouritesEnabled: enabled,
  favouritesDimmed: dimmed,
  onTap: (d, price) => taps?.grid.add('${d.id}@$price'),
  onFavouriteTap: (d, price) => taps?.favourites.add('${d.id}@$price'),
);

Finder quick(String id) => find.byKey(ValueKey('quick-$id'));
Finder tile(String id) => find.byKey(ValueKey('drink-$id'));
Iterable<Key> quickKeys(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            '${(w.key as ValueKey).value}'.startsWith('quick-'),
      ),
    )
    .map((w) => w.key!);

void main() {
  setUpAll(() async {
    final loader = FontLoader('Caveat')
      ..addFont(rootBundle.load('assets/fonts/Caveat-Variable.ttf'));
    await loader.load();
  });

  /// The board on the 16:9 target (1280×720 design px), below the space the
  /// header and the frame take on the drink screen.
  Future<void> pumpBoard(WidgetTester tester, DrinkBoardData data) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: themeFor(AppDesign.kreidetafel),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(43, 131, 43, 10),
            child: ChalkDrinkBoard(data),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('boxes show name and price; a tap adds the drink at its price', (
    tester,
  ) async {
    final taps = Taps();
    await pumpBoard(
      tester,
      data(groups: realAssortment(), quantities: {'b1': 2}, taps: taps),
    );
    expect(find.text('Bier'), findsOneWidget);
    expect(find.text('Limo & Saft'), findsOneWidget);
    expect(
      find.descendant(of: tile('b1'), matching: find.text('Bier 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile('b1'), matching: find.text('1,01$_nbsp€')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile('b1'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile('b0'), matching: find.text('0')),
      findsNothing,
    );
    await tester.tap(tile('l10'));
    expect(taps.grid, ['l10@110']);
  });

  testWidgets('the real assortment fits the 16:9 board without scrolling', (
    tester,
  ) async {
    await pumpBoard(
      tester,
      data(
        groups: realAssortment(),
        favourites: realAssortment()[0].$2.take(4).toList(),
      ),
    );
    for (final s in tester.stateList<ScrollableState>(
      find.byType(Scrollable),
    )) {
      expect(s.position.maxScrollExtent, lessThan(1));
    }
    for (final (_, drinks) in realAssortment()) {
      for (final d in drinks) {
        expect(tile(d.id).hitTestable(), findsOneWidget, reason: d.id);
        expect(tester.getRect(tile(d.id)).bottom, lessThanOrEqualTo(720));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the real assortment fills the 16:9 board', (tester) async {
    final groups = realAssortment();
    await pumpBoard(
      tester,
      data(groups: groups, favourites: groups[0].$2.take(4).toList()),
    );
    final board = tester.getRect(find.byType(ChalkDrinkBoard));
    final available = board.bottom - kChalkOrderBarRoom;
    final columns = <double, double>{}; // left -> lowest field bottom
    for (final (g, _) in groups) {
      final field = tester.getRect(find.byKey(ValueKey('chalk-field-${g.id}')));
      // 4 columns of ~182 px: no group can stack at this height.
      expect(field.width, greaterThanOrEqualTo(180), reason: g.name);
      columns[field.left] = math.max(columns[field.left] ?? 0, field.bottom);
    }
    expect(columns, hasLength(4));
    for (final MapEntry(key: left, value: bottom) in columns.entries) {
      expect(bottom, greaterThan(available - 24), reason: 'column at $left');
      expect(bottom, lessThanOrEqualTo(available), reason: 'column at $left');
    }
    // Capped boxes spread over their field: the single Wasser box sits in
    // the middle of the space below the heading, not at its top.
    final wasser = tester.getRect(find.byKey(const ValueKey('chalk-field-g4')));
    final below = Rect.fromLTRB(
      wasser.left,
      wasser.top + kChalkHeader,
      wasser.right,
      wasser.bottom,
    );
    expect(tester.getCenter(tile('w0')).dy, closeTo(below.center.dy, 2));
    // Alkoholfrei: three boxes with even gaps down to the field's bottom,
    // half a gap at the edges.
    final alk = tester.getRect(find.byKey(const ValueKey('chalk-field-g2')));
    final a0 = tester.getRect(tile('a0'));
    final a1 = tester.getRect(tile('a1'));
    final a2 = tester.getRect(tile('a2'));
    final gap = a1.top - a0.bottom;
    expect(gap, greaterThan(kChalkBoxGap));
    expect(a2.top - a1.bottom, closeTo(gap, 1));
    expect(a0.top - (alk.top + kChalkHeader), closeTo(gap / 2, 1));
    expect(alk.bottom - a2.bottom, closeTo(gap / 2, 1));
    final pils = tester.widget<Text>(
      find.descendant(of: tile('b0'), matching: find.text('Pils')),
    );
    expect(pils.style!.fontSize, greaterThanOrEqualTo(20));
  });

  testWidgets('two favourites: the board shows exactly those, in rank order', (
    tester,
  ) async {
    final taps = Taps();
    final groups = realAssortment();
    await pumpBoard(
      tester,
      data(
        groups: groups,
        favourites: [groups[2].$2[3], groups[0].$2[1]],
        taps: taps,
      ),
    );
    expect(find.text('Für dich'), findsOneWidget);
    expect(quickKeys(tester), [
      const ValueKey('quick-l3'),
      const ValueKey('quick-b1'),
    ]);
    expect(
      tester.getCenter(quick('l3')).dy,
      lessThan(tester.getCenter(quick('b1')).dy),
    );
    // Favourites are left of the fields.
    expect(
      tester.getRect(quick('l3')).right,
      lessThan(tester.getRect(tile('b0')).left),
    );
    expect(
      find.descendant(of: quick('l3'), matching: find.text('1,03$_nbsp€')),
      findsOneWidget,
    );
    await tester.tap(quick('b1'));
    expect(taps.favourites, ['b1@101']);
    expect(taps.grid, isEmpty);
  });

  testWidgets('no favourites: no board, the fields use the full width', (
    tester,
  ) async {
    await pumpBoard(tester, data(groups: realAssortment()));
    expect(find.text('Für dich'), findsNothing);
    expect(quickKeys(tester), isEmpty);
    expect(tester.getRect(tile('b0')).left, lessThan(43 + 30));
  });

  testWidgets('favourites are dimmed and inert while a grid order is pending', (
    tester,
  ) async {
    final taps = Taps();
    final groups = realAssortment();
    await pumpBoard(
      tester,
      data(
        groups: groups,
        favourites: [groups[0].$2[0], groups[1].$2[0]],
        quantities: {'l0': 1},
        enabled: false,
        dimmed: true,
        taps: taps,
      ),
    );
    final opacity = tester
        .widget<Opacity>(
          find.ancestor(of: quick('b0'), matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(opacity, lessThan(1));
    await tester.tap(quick('b0'), warnIfMissed: false);
    expect(taps.favourites, isEmpty);
  });

  testWidgets('8 groups x 6 drinks: the last drink is reachable by scrolling', (
    tester,
  ) async {
    final taps = Taps();
    final groups = [
      for (var g = 0; g < 8; g++)
        (
          group('g$g', 'Gruppe $g', g),
          [
            for (var i = 0; i < 6; i++)
              drink('d$g-$i', 'Drink $g-$i', 'g$g', i),
          ],
        ),
    ];
    await pumpBoard(tester, data(groups: groups, taps: taps));
    expect(tester.takeException(), isNull);
    final last = tile('d7-5');
    await tester.scrollUntilVisible(
      last,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(last);
    expect(taps.grid, ['d7-5@105']);
    // Every group is on the board.
    for (var g = 0; g < 8; g++) {
      expect(find.text('Gruppe $g'), findsOneWidget);
    }
  });

  testWidgets('a 30-character name renders without overflow', (tester) async {
    expect(thirtyChars.length, 30);
    final groups = [
      (group('g1', 'Schnaps', 1), [drink('x', thirtyChars, 'g1', 0)]),
      ...realAssortment(),
    ];
    await pumpBoard(
      tester,
      data(groups: groups, favourites: [groups[0].$2[0]]),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: tile('x'), matching: find.text(thirtyChars)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quick('x'), matching: find.text(thirtyChars)),
      findsOneWidget,
    );
    final box = tester.getRect(tile('x'));
    expect(
      tester
          .getRect(
            find.descendant(of: tile('x'), matching: find.text(thirtyChars)),
          )
          .right,
      lessThanOrEqualTo(box.right),
    );
  });

  testWidgets('the real names are never cut; one name size per field', (
    tester,
  ) async {
    final groups = realNames();
    final favourites = [
      groups[0].$2[0],
      groups[1].$2[0],
      groups[2].$2[8],
      groups[3].$2[0],
    ];
    await pumpBoard(
      tester,
      data(groups: groups, favourites: favourites, quantities: {'n0-0': 2}),
    );
    expect(tester.takeException(), isNull);
    for (final (_, drinks) in groups) {
      final sizes = <double>{};
      for (final d in drinks) {
        final name = find.descendant(
          of: tile(d.id),
          matching: find.text(d.name),
        );
        expect(
          tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
          isFalse,
          reason: '${d.name} is cut',
        );
        sizes.add(tester.widget<Text>(name).style!.fontSize!);
      }
      expect(sizes, hasLength(1), reason: '$sizes');
    }
    for (final d in favourites) {
      final name = find.descendant(
        of: quick(d.id),
        matching: find.text(d.name),
      );
      expect(
        tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
        isFalse,
        reason: '${d.name} is cut on the favourites board',
      );
    }
    // Two words wrap rather than shrink to nothing.
    final krombacher = find.descendant(
      of: tile('n1-0'),
      matching: find.text('Krombacher alkoholfrei'),
    );
    expect(
      tester.renderObject<RenderParagraph>(krombacher).size.height,
      greaterThan(tester.widget<Text>(krombacher).style!.fontSize! * 1.5),
    );
    // The badge sits on the box's top right corner, not in the row.
    final box = tester.getRect(tile('n0-0'));
    final badge = tester.getCenter(
      find.descendant(of: tile('n0-0'), matching: find.text('2')),
    );
    expect(badge.dx, greaterThan(box.right - 24));
    expect(badge.dy, lessThan(box.top + 16));
  });
}
