import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/design/chalk/chalk_board.dart';
import 'package:bar_tab/presentation/design/chalk/chalk_extras.dart';
import 'package:bar_tab/presentation/design/coaster/coaster_extras.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/keypad.dart';
import 'package:bar_tab/presentation/drinks/quantity_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/designs.dart';
import '../../fixtures/font_rules.dart';

void main() {
  forEachDesign(_sheetTests);
}

void _sheetTests(AppDesign design) {
  late int quantity;
  late int more;
  late int book;

  Future<void> pump(
    WidgetTester tester, {
    int initial = 3,
    int? crateSize = 20,
  }) async {
    tester.view.physicalSize = design == AppDesign.standard
        ? const Size(1280, 800)
        : const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    quantity = initial;
    more = 0;
    book = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: themeFor(design),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Align(
            // The drink screen centres the new designs' sheets.
            alignment: design == AppDesign.standard
                ? Alignment.centerRight
                : Alignment.center,
            child: StatefulBuilder(
              builder: (context, setState) => QuantitySheet(
                key: ValueKey(initial),
                design: design,
                drinkName: 'Lemon Fizz',
                unitPriceCents: 115,
                crateSize: crateSize,
                quantity: quantity,
                // Another line of 2,00 € plus this one.
                orderTotalCents: 200 + quantity * 115,
                onChanged: (q) => setState(() => quantity = q),
                onMore: () => more++,
                onBook: () => book++,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> press(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key('keypad-$key')));
    await tester.pump();
  }

  String field(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(QuantitySheet.fieldKey),
          matching: find.byType(Text),
        ),
      )
      .data!;

  testWidgets('shows drink, unit price, crate key, total and actions', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Lemon Fizz'), findsOneWidget);
    expect(find.text('Anzahl, je 1,15 €'), findsOneWidget);
    expect(find.text('Kasten (20)'), findsOneWidget);
    expect(find.text('Gesamt'), findsOneWidget);
    expect(find.text('5,45 €'), findsOneWidget);
    expect(find.text('Weitere Getränke'), findsOneWidget);
    expect(find.text('Buchen'), findsOneWidget);
    expect(find.text('Verwerfen'), findsNothing);
    expect(field(tester), '3');
  });

  testWidgets('first key replaces the number, later keys append', (
    tester,
  ) async {
    await pump(tester);
    await press(tester, '2');
    expect(quantity, 2);
    await press(tester, '4');
    expect(quantity, 24);
    expect(field(tester), '24');
    expect(find.text('29,60 €'), findsOneWidget);
  });

  testWidgets('more than three digits is ignored (max 999)', (tester) async {
    await pump(tester);
    for (final k in ['9', '9', '9', '9']) {
      await press(tester, k);
    }
    expect(quantity, 999);
  });

  testWidgets('backspace to empty shows 0, then digits start fresh', (
    tester,
  ) async {
    await pump(tester, initial: 24);
    await press(tester, 'backspace');
    expect(quantity, 2);
    await press(tester, 'backspace');
    expect(quantity, 0);
    expect(field(tester), '0');
    await press(tester, 'backspace');
    expect(quantity, 0);
    await press(tester, '5');
    expect(quantity, 5);
  });

  // Maintainer decision: value = crates × crate size + typed number.
  Future<void> keys(WidgetTester tester, List<String> ks) async {
    for (final k in ks) {
      await press(tester, k);
    }
  }

  testWidgets('crate key discards the opened quantity: 3, Kasten -> 20', (
    tester,
  ) async {
    await pump(tester);
    await press(tester, 'crate');
    expect(quantity, 20);
  });

  testWidgets('each crate press adds a crate', (tester) async {
    await pump(tester);
    await keys(tester, ['crate', 'crate']);
    expect(quantity, 40);
    await press(tester, 'crate');
    expect(quantity, 60);
  });

  testWidgets('digits after a crate add on top', (tester) async {
    await pump(tester);
    await keys(tester, ['crate', '2']);
    expect(quantity, 22);
    await pump(tester, initial: 5);
    await keys(tester, ['crate', '1', '2']);
    expect(quantity, 32);
  });

  testWidgets('digits before a crate count too: 7, Kasten -> 27', (
    tester,
  ) async {
    await pump(tester);
    await keys(tester, ['7', 'crate']);
    expect(quantity, 27);
  });

  testWidgets('backspace removes typed digits, then crates', (tester) async {
    await pump(tester);
    await keys(tester, ['crate', '2']);
    await press(tester, 'backspace');
    expect(quantity, 20);
    await press(tester, 'backspace');
    expect(quantity, 0);
  });

  testWidgets('crates stop at 999', (tester) async {
    await pump(tester);
    for (var i = 0; i < 50; i++) {
      await press(tester, 'crate');
    }
    expect(quantity, 980);
    await keys(tester, ['1', '9']);
    expect(quantity, 999);
    await press(tester, '0');
    expect(quantity, 999);
  });

  testWidgets('minus borrows from a crate, never below 0', (tester) async {
    await pump(tester);
    await press(tester, 'crate');
    await tester.tap(find.byKey(QuantitySheet.minusKey));
    await tester.pump();
    expect(quantity, 19);
    await tester.tap(find.byKey(QuantitySheet.plusKey));
    await tester.pump();
    expect(quantity, 20);
  });

  testWidgets('minus and plus step within 0..999', (tester) async {
    await pump(tester, initial: 1);
    await tester.tap(find.byKey(QuantitySheet.plusKey));
    await tester.pump();
    expect(quantity, 2);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(QuantitySheet.minusKey));
      await tester.pump();
    }
    expect(quantity, 0);

    await pump(tester, initial: 999);
    await tester.tap(find.byKey(QuantitySheet.plusKey));
    await tester.pump();
    expect(quantity, 999);
  });

  testWidgets('action buttons call back', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Weitere Getränke'));
    expect(more, 1);
    await tester.tap(find.text('Buchen'));
    expect(book, 1);
  });

  testWidgets('keypad has digits, crate, zero and backspace', (tester) async {
    await pump(tester);
    expect(find.byType(Keypad), findsOneWidget);
    for (final k in [...List.generate(10, (i) => '$i'), 'crate', 'backspace']) {
      expect(find.byKey(Key('keypad-$k')), findsOneWidget, reason: k);
    }
  });

  testWidgets('without a crate size there is no crate key', (tester) async {
    await pump(tester, crateSize: null);
    expect(find.byKey(const Key('keypad-crate')), findsNothing);
    expect(find.textContaining('Kasten'), findsNothing);
    expect(find.byKey(const Key('keypad-0')), findsOneWidget);
  });

  testWidgets('the sheet fits the screen and keeps the font rules', (
    tester,
  ) async {
    await pump(tester);
    final screen = Offset.zero & tester.view.physicalSize;
    final sheet = tester.getRect(find.byType(QuantitySheet));
    expect(screen.intersect(sheet), sheet);
    expectFontRules(tester);
  });

  if (design == AppDesign.kreidetafel) {
    testWidgets('a framed slate board with chalk-circle keys', (tester) async {
      await pump(tester);
      expect(
        find.descendant(
          of: find.byType(QuantitySheet),
          matching: find.byType(ChalkBoard),
        ),
        findsOneWidget,
      );
      for (final k in ['1', '0', 'crate', 'backspace']) {
        expect(
          find.descendant(
            of: find.byKey(Key('keypad-$k')),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is ChalkCirclePainter,
            ),
          ),
          findsOneWidget,
          reason: k,
        );
      }
      // The quantity in large yellow chalk.
      final qty = tester.widget<Text>(
        find.descendant(
          of: find.byKey(QuantitySheet.fieldKey),
          matching: find.byType(Text),
        ),
      );
      expect(qty.style?.color, tokensFor(design).accent);
      expect(qty.style!.fontSize, greaterThanOrEqualTo(56));
    });
  }

  if (design == AppDesign.bierdeckel) {
    testWidgets('a round coaster carries the keypad, the buttons sit beside', (
      tester,
    ) async {
      await pump(tester);
      final disc = tester.getRect(find.byType(SheetCoaster));
      expect(disc.width, disc.height);
      bool inside(Finder f) =>
          (tester.getCenter(f) - disc.center).distance < disc.width / 2;
      for (final k in [...List.generate(10, (i) => '$i'), 'crate']) {
        expect(inside(find.byKey(Key('keypad-$k'))), isTrue, reason: k);
      }
      expect(inside(find.byKey(QuantitySheet.fieldKey)), isTrue);
      expect(inside(find.text('Lemon Fizz')), isTrue);
      expect(inside(find.text('Buchen')), isFalse);
      expect(inside(find.text('Weitere Getränke')), isFalse);
      // "Kasten" in the accent colour.
      final crate = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(const Key('keypad-crate')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(crate.color, tokensFor(design).accent);
    });
  }
}
