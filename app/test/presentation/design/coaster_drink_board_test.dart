import 'dart:math' as math;

import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/design/coaster/coaster.dart';
import 'package:bar_tab/presentation/design/coaster/coaster_drink_board.dart';
import 'package:bar_tab/presentation/design/coaster_plan.dart';
import 'package:bar_tab/presentation/design/coaster_text.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/drink_board_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _nbsp = ' ';
const thirtyChars = 'Schwarzwaldkirschwasserbrandls';

/// Where the board sits on the drink screen at 1280×720: screen padding
/// left/right, the compact header above (measured with the real fonts).
const _padding = EdgeInsets.fromLTRB(33, 82, 33, 0);

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

DrinkGroup group(String id, String name, int sort, {int color = 0xFFB5651D}) =>
    DrinkGroup(id: id, name: name, sortOrder: sort, color: color);

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
    group('g2', 'Alkoholfrei', 2, color: 0xFF3D7A3A),
    [for (var i = 0; i < 3; i++) drink('a$i', 'Frei $i', 'g2', i)],
  ),
  (
    group('g3', 'Limo & Saft', 3, color: 0xFFA02F6E),
    [for (var i = 0; i < 11; i++) drink('l$i', 'Limo $i', 'g3', i)],
  ),
  (
    group('g4', 'Wasser', 4, color: 0xFF2B6AA0),
    [drink('w0', 'Wasser', 'g4', 0)],
  ),
];

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
  colorOf: (d) => const Color(0xFFB5651D),
  quantities: quantities,
  favourites: favourites,
  favouritesEnabled: enabled,
  favouritesDimmed: dimmed,
  onTap: (d, price) => taps?.grid.add('${d.id}@$price'),
  onFavouriteTap: (d, price) => taps?.favourites.add('${d.id}@$price'),
);

Finder quick(String id) => find.byKey(ValueKey('quick-$id'));
Finder tile(String id) => find.byKey(ValueKey('drink-$id'));
Finder hub(String groupId) => find.byKey(ValueKey('coaster-hub-$groupId'));
Finder block(String groupId) => find.byKey(ValueKey('coaster-block-$groupId'));
Iterable<Key> quickKeys(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            '${(w.key as ValueKey).value}'.startsWith('quick-'),
      ),
    )
    .map((w) => w.key!);

/// Distances of the drinks' centres from their hub's centre, rounded.
List<double> radii(WidgetTester tester, String groupId, List<String> ids) {
  final c = tester.getCenter(hub(groupId));
  return [
    for (final id in ids)
      ((tester.getCenter(tile(id)) - c).distance * 10).round() / 10,
  ];
}

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

void main() {
  // The real fonts: text fitting depends on them.
  setUpAll(() async {
    final alfa = FontLoader('Alfa Slab One')
      ..addFont(rootBundle.load('assets/fonts/AlfaSlabOne-Regular.ttf'));
    await alfa.load();
    final barlow = FontLoader('Barlow Condensed');
    for (final face in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
      barlow.addFont(rootBundle.load('assets/fonts/BarlowCondensed-$face.ttf'));
    }
    await barlow.load();
  });

  Widget app(DrinkBoardData data) => MaterialApp(
    theme: themeFor(AppDesign.bierdeckel),
    locale: const Locale('de'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Padding(padding: _padding, child: CoasterDrinkBoard(data)),
    ),
  );

  /// The board on the 16:9 target (1280×720 design px).
  Future<void> pumpBoard(WidgetTester tester, DrinkBoardData data) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(data));
    await tester.pump();
  }

  testWidgets(
    'coasters show name and price; a tap adds the drink at its price',
    (tester) async {
      final taps = Taps();
      await pumpBoard(
        tester,
        data(groups: realAssortment(), quantities: {'b1': 2}, taps: taps),
      );
      expect(
        find.descendant(of: hub('g1'), matching: find.text('Bier')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hub('g3'), matching: find.text('Limo & Saft')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile('b1'), matching: find.text('Bier 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile('b1'), matching: find.text('1,01$_nbsp€')),
        findsOneWidget,
      );
      // The pending quantity as a badge; none without one.
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
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the hub and the drink rings take the group colour', (
    tester,
  ) async {
    await pumpBoard(tester, data(groups: realAssortment()));
    final coaster = tester.widget<Coaster>(tile('a1'));
    expect(coaster.ring, const Color(0xFF3D7A3A));
    expect(coaster.highlighted, isFalse);
    final hubCoaster = tester.widget<CoasterHub>(hub('g2'));
    expect(hubCoaster.color, const Color(0xFF3D7A3A));
  });

  testWidgets('a group of 11 puts 7 coasters on the inner, 4 on a wider ring', (
    tester,
  ) async {
    await pumpBoard(tester, data(groups: realAssortment()));
    final r = radii(tester, 'g3', [for (var i = 0; i < 11; i++) 'l$i']);
    final distinct = r.toSet().toList()..sort();
    expect(distinct, hasLength(2), reason: '$r');
    expect(r.where((x) => x == distinct[0]), hasLength(7));
    expect(r.where((x) => x == distinct[1]), hasLength(4));
    // Spread evenly: neighbours on the inner ring are 360°/7 apart.
    final c = tester.getCenter(hub('g3'));
    final angles = [
      for (var i = 0; i < 7; i++) (tester.getCenter(tile('l$i')) - c).direction,
    ]..sort();
    for (var i = 1; i < 7; i++) {
      expect(angles[i] - angles[i - 1], closeTo(2 * math.pi / 7, 0.01));
    }
  });

  testWidgets('a group of 9 puts all 9 coasters on one ring', (tester) async {
    final groups = [
      (
        group('g9', 'Neun', 1),
        [for (var i = 0; i < 9; i++) drink('n$i', 'N $i', 'g9', i)],
      ),
    ];
    await pumpBoard(tester, data(groups: groups));
    final r = radii(tester, 'g9', [for (var i = 0; i < 9; i++) 'n$i']);
    expect(r.toSet(), hasLength(1), reason: '$r');
  });

  testWidgets('the real assortment fills the 16:9 board without scrolling', (
    tester,
  ) async {
    final groups = realAssortment();
    await pumpBoard(
      tester,
      data(groups: groups, favourites: groups[0].$2.take(4).toList()),
    );
    for (final s in tester.stateList<ScrollableState>(
      find.byType(Scrollable),
    )) {
      expect(s.position.maxScrollExtent, lessThan(1));
    }
    final board = tester.getRect(find.byType(CoasterDrinkBoard));
    final area = Rect.fromLTRB(
      board.left + kCoasterTrayWidth + kCoasterTrayGap,
      board.top,
      board.right,
      board.bottom - kCoasterOrderBarRoom,
    );
    // The largest coaster step that fits 4 groups next to the tray.
    final plan = planCoasterBoard([5, 3, 11, 1], area.size);
    expect(plan.coaster, greaterThanOrEqualTo(60));
    expect(tester.getSize(tile('b0')).width, plan.coaster);

    for (final (_, drinks) in groups) {
      for (final d in drinks) {
        expect(tile(d.id).hitTestable(), findsOneWidget, reason: d.id);
        final rect = tester.getRect(tile(d.id));
        expect(rect.bottom, lessThanOrEqualTo(area.bottom), reason: d.id);
        expect(rect.right, lessThanOrEqualTo(area.right), reason: d.id);
      }
    }
    final used = [
      for (final (g, _) in groups) tester.getRect(block(g.id)),
    ].reduce((a, b) => a.expandToInclude(b));
    // Centred on the board, vertically and horizontally ...
    expect(used.left - area.left, greaterThan(10));
    expect(used.left - area.left, closeTo(area.right - used.right, 1));
    expect(used.top - area.top, closeTo(area.bottom - used.bottom, 1));
    // ... and spread: the columns span the width, not packed together.
    expect(used.width, greaterThan(area.width * 0.9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('four favourites lie on the tray as large gold-rimmed coasters', (
    tester,
  ) async {
    final taps = Taps();
    final groups = realAssortment();
    final favourites = [
      groups[2].$2[3],
      groups[0].$2[1],
      ...groups[1].$2.take(2),
    ];
    await pumpBoard(
      tester,
      data(groups: groups, favourites: favourites, taps: taps),
    );
    expect(find.text('DEIN TABLETT'), findsOneWidget);
    expect(quickKeys(tester), [
      for (final d in favourites) ValueKey('quick-${d.id}'),
    ]);
    for (final d in favourites) {
      final coaster = tester.widget<Coaster>(quick(d.id));
      expect(coaster.highlighted, isTrue);
      expect(coaster.diameter, greaterThan(tester.getSize(tile('b0')).width));
      expect(
        tester.getRect(quick(d.id)).right,
        lessThan(tester.getRect(hub('g1')).left),
      );
    }
    // Top to bottom in rank order, each slightly turned.
    final ys = [for (final d in favourites) tester.getCenter(quick(d.id)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    for (final d in favourites) {
      final turn = tester.widget<Transform>(
        find.ancestor(of: quick(d.id), matching: find.byType(Transform)).first,
      );
      expect(turn.transform.entry(1, 0), isNot(0), reason: d.id);
    }
    expect(
      find.descendant(of: quick('l3'), matching: find.text('1,03$_nbsp€')),
      findsOneWidget,
    );
    await tester.tap(quick('b1'));
    expect(taps.favourites, ['b1@101']);
    expect(taps.grid, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two favourites: exactly those, same size, spread on the tray', (
    tester,
  ) async {
    final groups = realAssortment();
    await pumpBoard(
      tester,
      data(groups: groups, favourites: groups[0].$2.take(4).toList()),
    );
    final four = tester.widget<Coaster>(quick('b0')).diameter;
    await tester.pumpWidget(
      app(data(groups: groups, favourites: [groups[2].$2[3], groups[0].$2[1]])),
    );
    await tester.pump();
    expect(quickKeys(tester), [
      const ValueKey('quick-l3'),
      const ValueKey('quick-b1'),
    ]);
    expect(tester.widget<Coaster>(quick('l3')).diameter, four);
    final gap =
        tester.getRect(quick('b1')).top - tester.getRect(quick('l3')).bottom;
    expect(gap, greaterThan(four / 2));
  });

  testWidgets('no favourites: no tray, the rings use the full width', (
    tester,
  ) async {
    await pumpBoard(tester, data(groups: realAssortment()));
    expect(find.text('DEIN TABLETT'), findsNothing);
    expect(quickKeys(tester), isEmpty);
    final hubs = [
      for (final g in ['g1', 'g2', 'g3', 'g4']) hub(g),
    ];
    final left = hubs.map((h) => tester.getRect(h).left).reduce(math.min);
    expect(left, lessThan(33 + 236));
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
    expect(opacity, 0.35);
    await tester.tap(quick('b0'), warnIfMissed: false);
    expect(taps.favourites, isEmpty);
  });

  testWidgets(
    '8 groups x 30 drinks: the last drink is reachable by scrolling',
    (tester) async {
      final taps = Taps();
      final groups = [
        for (var g = 0; g < 8; g++)
          (
            group('g$g', 'Gruppe $g', g),
            [
              for (var i = 0; i < 30; i++)
                drink('d$g-$i', 'Drink $g-$i', 'g$g', i),
            ],
          ),
      ];
      await pumpBoard(tester, data(groups: groups, taps: taps));
      expect(tester.takeException(), isNull);
      // Every group is on the board.
      for (var g = 0; g < 8; g++) {
        expect(hub('g$g'), findsOneWidget);
      }
      // Coasters stay large enough to hit.
      for (final e in tester.widgetList<Coaster>(find.byType(Coaster))) {
        expect(e.diameter, greaterThanOrEqualTo(44));
      }
      expect(tester.getSize(tile('d0-0')).width, greaterThanOrEqualTo(44));
      final last = tile('d7-29');
      await tester.scrollUntilVisible(
        last,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(last);
      expect(taps.grid, ['d7-29@129']);
    },
  );

  testWidgets('coaster tap targets are at least 44 px', (tester) async {
    final groups = realAssortment();
    await pumpBoard(
      tester,
      data(groups: groups, favourites: groups[0].$2.take(4).toList()),
    );
    for (final (_, drinks) in groups) {
      for (final d in drinks) {
        final size = tester.getSize(tile(d.id));
        expect(size.shortestSide, greaterThanOrEqualTo(44), reason: d.id);
      }
    }
    expect(tester.getSize(quick('b0')).shortestSide, greaterThanOrEqualTo(44));
  });

  testWidgets('a 30-character name renders without an exception', (
    tester,
  ) async {
    expect(thirtyChars.length, 30);
    final groups = [
      (group('g0', 'Schnaps', 0), [drink('x', thirtyChars, 'g0', 0)]),
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
  });

  testWidgets('rebuilding with the same drinks keeps the fitted names', (
    tester,
  ) async {
    // The order bar countdown rebuilds the screen every second; the
    // coasters must not fit their text again each time.
    final groups = realAssortment();
    await pumpBoard(tester, data(groups: groups, quantities: {'b1': 1}));
    CoasterText name() => tester.widget<CoasterText>(
      find.descendant(of: tile('b0'), matching: find.byType(CoasterText)),
    );
    final before = name();
    await tester.pumpWidget(app(data(groups: groups, quantities: {'b1': 1})));
    expect(identical(name(), before), isTrue);
  });

  testWidgets('the real names are never cut; coasters at 66 px or larger', (
    tester,
  ) async {
    final groups = realNames();
    final favourites = [
      groups[0].$2[0],
      groups[1].$2[0],
      groups[2].$2[8],
      groups[3].$2[0],
    ];
    await pumpBoard(tester, data(groups: groups, favourites: favourites));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(tile('n0-0')).width, greaterThanOrEqualTo(66));
    RenderParagraph paragraph(Finder of, String text) =>
        tester.renderObject<RenderParagraph>(
          find.descendant(of: of, matching: find.text(text)),
        );
    for (final (g, drinks) in groups) {
      for (final d in drinks) {
        expect(
          paragraph(tile(d.id), d.name).didExceedMaxLines,
          isFalse,
          reason: '${d.name} is cut',
        );
      }
      // The group name stays inside its hub.
      final name = paragraph(hub(g.id), g.name);
      expect(name.didExceedMaxLines, isFalse, reason: g.name);
      expect(
        name.size.width,
        lessThanOrEqualTo(tester.getSize(hub(g.id)).width),
        reason: g.name,
      );
    }
    for (final d in favourites) {
      expect(
        paragraph(quick(d.id), d.name).didExceedMaxLines,
        isFalse,
        reason: '${d.name} is cut on the tray',
      );
    }
    // The blocks spread over the board next to the slim tray.
    final board = tester.getRect(find.byType(CoasterDrinkBoard));
    final used = [
      for (final (g, _) in groups) tester.getRect(block(g.id)),
    ].reduce((a, b) => a.expandToInclude(b));
    final left = board.left + kCoasterTrayWidth + kCoasterTrayGap;
    expect(used.width, greaterThan((board.right - left) * 0.9));
  });
}
