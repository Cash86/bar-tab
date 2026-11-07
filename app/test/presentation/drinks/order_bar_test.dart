import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/order_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/designs.dart';

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
    });
  });
}
