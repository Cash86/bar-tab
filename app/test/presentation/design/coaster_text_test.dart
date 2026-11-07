import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bar_tab/presentation/design/coaster_text.dart';

const style = TextStyle(fontFamily: 'Alfa Slab One', fontSize: 15);
const fortyChars = 'Donaudampfschifffahrtsgesellschaftskapit';

const names = ['Anna', 'Krombacher alkoholfrei', 'Maximilian', fortyChars];

void main() {
  setUpAll(() async {
    final loader = FontLoader('Alfa Slab One')
      ..addFont(rootBundle.load('assets/fonts/AlfaSlabOne-Regular.ttf'));
    await loader.load();
  });

  group('fitCoasterText', () {
    test('a short name keeps the base size on one line', () {
      final fit = fitCoasterText('Anna', 72, style);
      expect(fit.fontSize, 15);
      expect(fit.lines, 1);
      expect(fit.overflowsRim, isFalse);
      expect(fit.ellipsized, isFalse);
    });

    test('several short words wrap inside the coaster', () {
      final fit = fitCoasterText('Eistee Pfirsich', 72, style);
      expect(fit.lines, 2);
      expect(fit.fontSize, 15);
      expect(fit.overflowsRim, isFalse);
      expect(fit.ellipsized, isFalse);
    });

    test('several words wrap onto 2-3 lines without breaking a word', () {
      final fit = fitCoasterText('Krombacher alkoholfrei', 72, style);
      expect(fit.lines, inInclusiveRange(2, 3));
      expect(fit.ellipsized, isFalse);
      expect(fit.fontSize, inInclusiveRange(9, 15));
      // A word longer than the inner square widens the box, at most to
      // 1.15 * diameter, instead of being broken inside the word.
      expect(fit.width, inInclusiveRange(0.78 * 72, 1.15 * 72));
      final longest = TextPainter(
        text: TextSpan(
          text: 'Krombacher',
          style: style.copyWith(fontSize: fit.fontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(longest.width, lessThanOrEqualTo(fit.width));
      longest.dispose();
    });

    test('a long single word stays on one line and crosses the rim', () {
      final fit = fitCoasterText('Maximilian', 72, style);
      expect(fit.lines, 1);
      expect(fit.overflowsRim, isTrue);
      expect(fit.ellipsized, isFalse);
    });

    test('a hyphenated name is one word on one line', () {
      final fit = fitCoasterText('Hans-Joachim', 72, style);
      expect(fit.lines, 1);
      expect(fit.ellipsized, isFalse);
    });

    test('a long hyphenated word stays on one line, cut at the minimum', () {
      const name = 'Hans-Joachim-Maximilian-Friedrich';
      final fit = fitCoasterText(name, 72, style);
      expect(fit.lines, 1);
      expect(fit.fontSize, 9);
      expect(fit.ellipsized, isTrue);
      // Above the minimum it is never cut.
      final big = fitCoasterText(name, 72, style, minFontSize: 3);
      expect(big.lines, 1);
      expect(big.ellipsized, isFalse);
    });

    test('a 40-character single word is cut at the minimum size', () {
      final fit = fitCoasterText(fortyChars, 72, style);
      expect(fortyChars.length, 40);
      expect(fit.lines, 1);
      expect(fit.fontSize, 9);
      expect(fit.ellipsized, isTrue);
    });

    test('many words at the minimum size are cut on the third line', () {
      final fit = fitCoasterText(
        'Ein sehr langer Getraenkename mit vielen einzelnen Woertern darin',
        72,
        style,
      );
      expect(fit.lines, 3);
      expect(fit.fontSize, 9);
      expect(fit.ellipsized, isTrue);
    });
  });

  group('CoasterText', () {
    for (final name in names) {
      testWidgets('"$name" is drawn as stroke behind fill without overflow', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: CoasterText(
                  name,
                  diameter: 72,
                  style: style,
                  strokeColor: const Color(0xFF123456),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        // Findable by its name exactly once, as name tiles are today.
        expect(find.text(name), findsOneWidget);
        final layers = find.descendant(
          of: find.byType(CoasterText),
          matching: find.byType(RichText),
        );
        final paragraphs = tester
            .renderObjectList<RenderParagraph>(layers)
            .toList();
        expect(paragraphs, hasLength(2));
        for (final p in paragraphs) {
          expect(p.text.toPlainText(), name);
        }
        final stroke = paragraphs.first.text.style!.foreground!;
        expect(stroke.style, PaintingStyle.stroke);
        expect(stroke.strokeWidth, greaterThanOrEqualTo(3));
        expect(stroke.color.toARGB32(), 0xFF123456);
        expect(paragraphs.last.text.style!.foreground, isNull);
        // Only the over-long word is cut; the others are shown in full.
        for (final p in paragraphs) {
          expect(p.didExceedMaxLines, name == fortyChars);
        }
        expect(tester.getSize(find.byType(CoasterText)), const Size(72, 72));
      });
    }
  });
}
