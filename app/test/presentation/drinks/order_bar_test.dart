import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/design/chalk/chalk_board.dart';
import 'package:bar_tab/presentation/design/chalk/chalk_extras.dart';
import 'package:bar_tab/presentation/design/coaster/coaster.dart';
import 'package:bar_tab/presentation/design/coaster/coaster_extras.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/order_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/designs.dart';
import '../../fixtures/font_rules.dart';

const _fonts = {
  'Archivo': ['Archivo-Variable.ttf'],
  'Caveat': ['Caveat-Variable.ttf'],
  'Alfa Slab One': ['AlfaSlabOne-Regular.ttf'],
  'Barlow Condensed': [
    'BarlowCondensed-Regular.ttf',
    'BarlowCondensed-SemiBold.ttf',
    'BarlowCondensed-Bold.ttf',
    'BarlowCondensed-ExtraBold.ttf',
  ],
};

void main() {
  setUpAll(() async {
    for (final MapEntry(key: family, value: files) in _fonts.entries) {
      final loader = FontLoader(family);
      for (final f in files) {
        loader.addFont(rootBundle.load('assets/fonts/$f'));
      }
      await loader.load();
    }
  });

  forEachDesign((design) {
    testWidgets('the countdown repaints on its own layer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(design),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: OrderBar(
              design: design,
              summary: '1× Lager',
              totalCents: 120,
              secondsLeft: 5,
              countdownRun: 0,
              onDiscard: () {},
              onDone: () {},
            ),
          ),
        ),
      );
      // The strip animates every frame; it must not repaint the bar or the
      // board behind it.
      expect(
        tester.renderObject(find.byKey(const Key('order-bar-progress'))),
        isA<RenderRepaintBoundary>(),
      );
    });
  });

  forEachDesign((design) {
    testWidgets('with the real fonts the bar is exactly OrderBar.height', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(design),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 33),
                child: OrderBar(
                  design: design,
                  summary: '2× Lager, 1× Lemonade',
                  totalCents: 290,
                  secondsLeft: 5,
                  countdownRun: 0,
                  onDiscard: () {},
                  onDone: () {},
                ),
              ),
            ),
          ),
        ),
      );
      // The content decides the height: taller content would grow the bar
      // into the room boards keep for it.
      expect(tester.getSize(find.byType(OrderBar)).height, OrderBar.height);
      expectFontRules(tester);
    });
  });

  group('look per design', () {
    Future<void> pumpBar(WidgetTester tester, AppDesign design) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(design),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: OrderBar(
                design: design,
                summary: '1× Lager',
                totalCents: 120,
                secondsLeft: 5,
                countdownRun: 0,
                onDiscard: () {},
                onDone: () {},
              ),
            ),
          ),
        ),
      );
    }

    TextStyle style(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!;

    testWidgets('Kreidetafel: a slate strip with chalk text and boxes', (
      tester,
    ) async {
      final tokens = tokensFor(AppDesign.kreidetafel);
      await pumpBar(tester, AppDesign.kreidetafel);
      expect(
        find.descendant(
          of: find.byType(OrderBar),
          matching: find.byType(ChalkStrip),
        ),
        findsOneWidget,
      );
      expect(style(tester, '1× Lager').color, tokens.text);
      expect(style(tester, '1× Lager').fontFamily, 'Caveat');
      expect(style(tester, '1,20\u00A0€').color, tokens.accent);
      for (final label in ['Verwerfen', 'Fertig']) {
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is ChalkBorderPainter,
            ),
          ),
          findsOneWidget,
          reason: label,
        );
      }
      expectFontRules(tester);
    });

    testWidgets('Bierdeckel: cream receipt with the dark-red Fertig', (
      tester,
    ) async {
      final tokens = tokensFor(AppDesign.bierdeckel);
      await pumpBar(tester, AppDesign.bierdeckel);
      final bar = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(OrderBar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(bar.color, kReceiptPaper);
      expect(style(tester, '1× Lager').color, kCoasterInk);
      final done = tester.widget<Material>(
        find
            .ancestor(of: find.text('Fertig'), matching: find.byType(Material))
            .first,
      );
      expect(done.color, tokens.accent);
      expect(style(tester, 'Fertig').color, tokens.onAccent);
      expectFontRules(tester);
    });
  });
}
