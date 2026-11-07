import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/design/chalk/chalk_name_board.dart';
import 'package:bar_tab/presentation/design/coaster/coaster.dart';
import 'package:bar_tab/presentation/design/coaster/coaster_name_board.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/drink_selection_screen.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/designs.dart';

/// The 16:9 target: 1920×1080 at density 1.0, scaled to 1280×720.
const _screen = Size(1280, 720);

const _tiers = [
  PriceTier(id: 't1', name: 'Aktive', sortOrder: 1),
  PriceTier(id: 't2', name: 'Alte Herren', sortOrder: 2),
];

/// 20 characters each: one word (hyphenated) and several words.
const longWord = 'Maximilian-Friedrich';
const longWords = 'Anna Lena Marie Sofi';

Person person(
  String id,
  String name, {
  String tier = 't1',
  bool collective = false,
}) => Person(
  id: id,
  name: name,
  priceTierId: tier,
  isHidden: false,
  isCollective: collective,
  isActive: true,
);

const _active = [
  'Anna', 'Ben', 'Carla', 'David', 'Emil', 'Finn', 'Greta', 'Hannes', //
  'Ida', 'Jonas', 'Klara', 'Lukas', 'Mia', 'Noah', 'Paul',
];
const _seniors = [
  'Bernd', 'Dieter', 'Erwin', 'Franz', 'Gerhard', 'Helmut', 'Jürgen', //
  'Klaus', 'Manfred', 'Norbert', 'Otto', 'Rainer', 'Siegfried', 'Werner',
];

/// 3 collective accounts, 15 + 14 persons (the approved mockup); [extra]
/// replaces the first names of the first tier.
List<Person> realisticPersons({List<String> extra = const []}) => [
  person('c1', 'Stammtisch', collective: true),
  person('c2', 'Gästekasse', collective: true),
  person('c3', 'Vereinskasse', collective: true),
  for (var i = 0; i < _active.length; i++)
    person('a$i', i < extra.length ? extra[i] : _active[i]),
  for (var i = 0; i < _seniors.length; i++)
    person('s$i', _seniors[i], tier: 't2'),
];

Catalog catalogOf(List<Person> persons, {List<PriceTier> tiers = _tiers}) =>
    Catalog(
      tiers: tiers,
      persons: persons,
      groups: const [],
      drinks: const [],
      etag: 'e',
    );

const _l10n = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  // The real fonts: text fitting depends on them.
  setUpAll(() async {
    final caveat = FontLoader('Caveat')
      ..addFont(rootBundle.load('assets/fonts/Caveat-Variable.ttf'));
    await caveat.load();
    final alfa = FontLoader('Alfa Slab One')
      ..addFont(rootBundle.load('assets/fonts/AlfaSlabOne-Regular.ttf'));
    await alfa.load();
    final barlow = FontLoader('Barlow Condensed');
    for (final face in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
      barlow.addFont(rootBundle.load('assets/fonts/BarlowCondensed-$face.ttf'));
    }
    await barlow.load();
  });

  void setScreen(WidgetTester tester) {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    AppDesign design,
    Catalog catalog,
  ) async {
    setScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) async => catalog),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          designOverride(design),
        ],
        child: MaterialApp(
          theme: themeFor(design),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _l10n,
          home: const NameListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The design's own board, not Standard's tiles.
    expect(
      find.byType(
        design == AppDesign.kreidetafel ? ChalkNameBoard : CoasterNameBoard,
      ),
      findsOneWidget,
    );
  }

  Finder tile(String personId) => find.byKey(ValueKey('person-$personId'));

  for (final design in [AppDesign.kreidetafel, AppDesign.bierdeckel]) {
    group(design.name, () {
      testWidgets(
        '3 collective + 15 + 14 persons: all visible, the board is filled',
        (tester) async {
          await pumpScreen(tester, design, catalogOf(realisticPersons()));
          expect(find.byType(Scrollable), findsNothing);
          expect(find.text('Wer trinkt?'), findsOneWidget);
          final screen = Offset.zero & _screen;
          final rects = <Rect>[];
          for (final p in realisticPersons()) {
            expect(find.text(p.name), findsOneWidget, reason: p.name);
            final r = tester.getRect(tile(p.id));
            expect(screen.intersect(r), r, reason: '${p.name} at $r');
            expect(
              tester.getRect(find.text(p.name)).width,
              greaterThan(0),
              reason: p.name,
            );
            if (!p.isCollective) rects.add(r);
          }
          // No large empty areas: the persons reach the right edge and the
          // longer column reaches close to the bottom.
          final right = rects.fold<double>(
            0,
            (m, r) => r.right > m ? r.right : m,
          );
          final bottom = rects.fold<double>(
            0,
            (m, r) => r.bottom > m ? r.bottom : m,
          );
          expect(right, greaterThan(_screen.width - 110));
          expect(bottom, greaterThan(_screen.height - 130));
          // Tiles are as large as fit, not the minimum size.
          expect(tester.getSize(tile('a0')).height, greaterThan(72));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('40 persons in one tier: the column scrolls, the last name '
          'can be tapped', (tester) async {
        await pumpScreen(
          tester,
          design,
          catalogOf([
            person('c1', 'Stammtisch', collective: true),
            for (var i = 0; i < 40; i++)
              person('p$i', 'Name ${i.toString().padLeft(2, '0')}'),
          ]),
        );
        expect(find.byType(Scrollable), findsOneWidget);
        final collective = tester.getTopLeft(find.text('Stammtisch'));
        await tester.scrollUntilVisible(
          find.text('Name 39'),
          200,
          scrollable: find.byType(Scrollable),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('Stammtisch')), collective);
        await tester.tap(find.text('Name 39'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DrinkSelectionScreen>(find.byType(DrinkSelectionScreen))
              .personId,
          'p39',
        );
      });

      testWidgets('20-character names are shown whole, without overflow', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          design,
          catalogOf(realisticPersons(extra: [longWord, longWords])),
        );
        expect(tester.takeException(), isNull);
        for (final name in [longWord, longWords]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(name),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: name);
          // A single word is never broken inside the word.
          if (name == longWord) {
            expect(
              paragraph
                  .getBoxesForSelection(
                    const TextSelection(baseOffset: 0, extentOffset: 20),
                  )
                  .map((b) => b.top)
                  .toSet(),
              hasLength(1),
            );
          }
        }
      });

      testWidgets('tier colours follow the position among all tiers', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          design,
          catalogOf(
            [
              person('c1', 'Stammtisch', collective: true),
              person('a', 'Anton', tier: 't1'),
              person('c', 'Cleo', tier: 't3'),
            ],
            tiers: const [
              PriceTier(id: 't3', name: 'Third', sortOrder: 3),
              PriceTier(id: 't1', name: 'First', sortOrder: 1),
              PriceTier(id: 't2', name: 'Second', sortOrder: 2),
            ],
          ),
        );
        final tokens = tokensFor(design);
        Color? colorOf(String text) =>
            tester.widget<Text>(find.textContaining(text)).style?.color;
        if (design == AppDesign.kreidetafel) {
          expect(colorOf('First'), tokens.tierColor(0));
          expect(colorOf('Third'), tokens.tierColor(2));
          // Collective accounts in yellow chalk.
          expect(colorOf('Stammtisch'), const Color(0xFFFFF3C4));
        } else {
          final cleo = tester.widget<Coaster>(tile('c'));
          expect(cleo.ring, tokens.tierColor(2));
          expect(cleo.highlighted, isFalse);
          final team = tester.widget<Coaster>(tile('c1'));
          expect(team.highlighted, isTrue);
          expect(team.diameter, greaterThan(cleo.diameter));
        }
        expect(find.textContaining('Second'), findsNothing);
        expect(find.textContaining('SECOND'), findsNothing);
      });

      testWidgets('a disabled board (tap guard) ignores taps', (tester) async {
        setScreen(tester);
        final tapped = <String>[];
        Widget board({required bool enabled}) {
          final collective = [person('c1', 'Stammtisch', collective: true)];
          final tiers = [
            (_tiers[0], [person('a', 'Anton')]),
          ];
          void onTap(Person p) => tapped.add(p.id);
          Color tierColor(PriceTier t) => tokensFor(design).tierColor(0);
          return switch (design) {
            AppDesign.kreidetafel => ChalkNameBoard(
              collective: collective,
              tiers: tiers,
              tierColor: tierColor,
              onTap: onTap,
              enabled: enabled,
            ),
            _ => CoasterNameBoard(
              collective: collective,
              tiers: tiers,
              tierColor: tierColor,
              onTap: onTap,
              enabled: enabled,
            ),
          };
        }

        Future<void> pumpBoard({required bool enabled}) => tester.pumpWidget(
          MaterialApp(
            theme: themeFor(design),
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: _l10n,
            home: Scaffold(body: board(enabled: enabled)),
          ),
        );

        await pumpBoard(enabled: false);
        await tester.tap(find.text('Anton'), warnIfMissed: false);
        await tester.tap(find.text('Stammtisch'), warnIfMissed: false);
        await tester.pump();
        expect(tapped, isEmpty);

        await pumpBoard(enabled: true);
        await tester.tap(find.text('Anton'));
        await tester.tap(find.text('Stammtisch'));
        await tester.pump();
        expect(tapped, ['a', 'c1']);
      });
    });
  }
}
