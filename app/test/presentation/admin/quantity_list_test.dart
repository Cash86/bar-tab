import 'dart:convert';

import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/quantity_list.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fakes.dart';

Drink _drink(
  String id,
  String name, {
  String group = 'g1',
  int crate = 20,
  bool hidden = false,
  bool active = true,
}) => Drink(
  id: id,
  name: name,
  groupId: group,
  crateSize: crate,
  sortOrder: 1,
  isHidden: hidden,
  isActive: active,
  prices: const {},
);

void main() {
  late QuantityLines lines;
  const groups = [
    DrinkGroup(id: 'g2', name: 'Softdrinks', sortOrder: 2, color: 0xFF2196F3),
    DrinkGroup(id: 'g1', name: 'Bier', sortOrder: 1, color: 0xFFFFC107),
  ];
  final drinks = [
    _drink('d1', 'Pils'),
    _drink('d2', 'Alt Old', active: false),
    _drink('d3', 'Geheim', hidden: true),
    _drink('d4', 'Wasser', group: 'g2', crate: 1),
  ];

  group('draft round trip', () {
    test('keeps counts and an entered zero', () {
      lines.select('d1');
      lines.digit(2);
      lines.focusCrates(false);
      lines.digit(0);
      lines.select('d4', hasCrates: false);
      lines.digit(5);
      final json =
          jsonDecode(jsonEncode(lines.toJson())) as Map<String, dynamic>;

      final restored = QuantityLines(crateSizeOf: (_) => 20)..restore(json);
      expect(restored.cratesOf('d1'), 2);
      expect(restored.unitsOf('d4'), 5);
      expect(restored.toJson(), lines.toJson());
      expect((restored.toJson()['units'] as Map).containsKey('d1'), isTrue);
    });

    test('restore replaces state and notifies', () {
      lines.select('d1');
      lines.digit(7);
      var notified = 0;
      lines.addListener(() => notified++);
      lines.restore({
        'crates': {'d4': 3},
        'units': <String, dynamic>{},
      });
      expect(lines.cratesOf('d1'), 0);
      expect(lines.cratesOf('d4'), 3);
      expect(notified, 1);
    });
  });

  setUp(() => lines = QuantityLines());

  Future<void> pump(
    WidgetTester tester, {
    String Function(Drink, int)? trailing,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [configStoreProvider.overrideWithValue(pairedStore())],
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: QuantityList(
              drinks: drinks,
              groups: groups,
              lines: lines,
              trailing: trailing,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> keys(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
  }

  testWidgets('keypad fills the focused field, chips switch it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('qty-row-d1')));
    await tester.pump();
    await keys(tester, '2');
    await tester.tap(find.byKey(const Key('qty-chip-units')));
    await tester.pump();
    await keys(tester, '3');
    expect(lines.cratesOf('d1'), 2);
    expect(lines.unitsOf('d1'), 3);
    expect(find.text('= 43'), findsOneWidget);
    expect(lines.totals({'d1': 20}), {'d1': 43});
    await tester.tap(find.byKey(const Key('keypad-backspace')));
    await tester.pump();
    expect(lines.unitsOf('d1'), 0);
  });

  testWidgets('fields take at most four digits', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('qty-row-d1')));
    await tester.pump();
    await keys(tester, '12345');
    expect(lines.cratesOf('d1'), 1234);
  });

  testWidgets('a crate size of 1 shows no crate chip', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('qty-row-d4')));
    await tester.pump();
    expect(find.byKey(const Key('qty-chip-crates')), findsNothing);
    expect(find.byKey(const Key('qty-crates-d4')), findsNothing);
    expect(find.byKey(const Key('qty-chip-units')), findsOneWidget);
    await keys(tester, '5');
    expect(lines.unitsOf('d4'), 5);
    expect(lines.cratesOf('d4'), 0);
  });

  testWidgets('panel shows the crate size', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('qty-row-d1')));
    await tester.pump();
    expect(find.text('Kasten = 20 Einheiten'), findsOneWidget);
  });

  testWidgets('inactive drinks are absent, hidden ones present, by group', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Alt Old'), findsNothing);
    expect(find.text('Geheim'), findsOneWidget);
    expect(find.text('Pils'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Bier')).dy,
      lessThan(tester.getTopLeft(find.text('Softdrinks')).dy),
    );
  });

  testWidgets('trailing builds the extra text from drink and units', (
    tester,
  ) async {
    await pump(tester, trailing: (d, units) => '${d.name}:$units');
    await tester.tap(find.byKey(const Key('qty-row-d1')));
    await tester.pump();
    await keys(tester, '1');
    expect(find.text('Pils:20'), findsOneWidget);
  });

  test('select focuses units for a drink without crates, notifying once', () {
    var notified = 0;
    lines.addListener(() => notified++);
    lines.select('d4', hasCrates: false);
    expect(lines.crateFocused, isFalse);
    expect(notified, 1);
    lines.select('d1');
    expect(lines.crateFocused, isTrue);
    expect(notified, 2);
  });

  testWidgets('the empty panel shows a hint until a row is tapped', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Getränk antippen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('qty-row-d1')));
    await tester.pump();
    expect(find.text('Getränk antippen'), findsNothing);
  });

  testWidgets('the crates field reads "n K"', (tester) async {
    await pump(tester);
    expect(find.text('0 K'), findsNWidgets(2));
  });

  testWidgets('a long trailing text neither wraps nor overflows', (
    tester,
  ) async {
    await pump(tester, trailing: (d, units) => '1.234,50 € brutto');
    await tester.tap(find.byKey(const Key('qty-row-d1')));
    await tester.pump();
    await keys(tester, '1');
    final text = find.text('1.234,50 € brutto');
    expect(text, findsOneWidget);
    expect(tester.getSize(text).height, lessThan(30));
    expect(tester.takeException(), isNull);
  });
}
