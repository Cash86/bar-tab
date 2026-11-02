import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/drinks/keypad.dart';
import 'package:bar_tab/presentation/drinks/quantity_sheet.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int quantity;
  late int more;
  late int book;

  Future<void> pump(WidgetTester tester, {int initial = 3}) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    quantity = initial;
    more = 0;
    book = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: BarTabTheme.data,
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
            alignment: Alignment.centerRight,
            child: StatefulBuilder(
              builder: (context, setState) => QuantitySheet(
                drinkName: 'Lemon Fizz',
                unitPriceCents: 115,
                crateSize: 20,
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

  testWidgets('crate key sets the crate size', (tester) async {
    await pump(tester);
    await press(tester, '7');
    await press(tester, 'crate');
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
}
