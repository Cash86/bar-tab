import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bar_tab/presentation/design/chalk_text.dart';

const style = TextStyle(fontFamily: 'Caveat', fontSize: 28);
const fortyChars = 'Donaudampfschifffahrtsgesellschaftskapit';

Widget boxed(String text) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 120,
        height: 40,
        child: ChalkText(text, style: style),
      ),
    ),
  ),
);

Widget sized(String text, Size size, {int maxLines = 1}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox.fromSize(
        size: size,
        child: ChalkText(text, style: style, maxLines: maxLines),
      ),
    ),
  ),
);

int lineCount(WidgetTester tester, String text) => paragraph(tester, text)
    .getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    )
    .map((b) => b.top)
    .toSet()
    .length;

RenderParagraph paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

void main() {
  setUpAll(() async {
    final loader = FontLoader('Caveat')
      ..addFont(rootBundle.load('assets/fonts/Caveat-Variable.ttf'));
    await loader.load();
  });

  testWidgets('a short name keeps its size', (tester) async {
    await tester.pumpWidget(boxed('Anna'));
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text('Anna')).style!.fontSize, 28);
    expect(paragraph(tester, 'Anna').didExceedMaxLines, isFalse);
  });

  testWidgets('a longer name shrinks to fit without being cut', (tester) async {
    await tester.pumpWidget(boxed('Bartholomaeus'));
    expect(tester.takeException(), isNull);
    final size = tester
        .widget<Text>(find.text('Bartholomaeus'))
        .style!
        .fontSize!;
    expect(size, lessThan(28));
    expect(size, greaterThanOrEqualTo(14));
    expect(paragraph(tester, 'Bartholomaeus').didExceedMaxLines, isFalse);
  });

  testWidgets('a 40-character name in a 120-px box is cut at the minimum', (
    tester,
  ) async {
    await tester.pumpWidget(boxed(fortyChars));
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text(fortyChars)).style!.fontSize, 14);
    expect(paragraph(tester, fortyChars).didExceedMaxLines, isTrue);
    expect(tester.getSize(find.text(fortyChars)).width, lessThanOrEqualTo(120));
  });

  testWidgets('a single long word is never broken: one line, cut with …', (
    tester,
  ) async {
    const word = 'Johannisbeerschorle';
    expect(word.length, 19);
    await tester.pumpWidget(sized(word, const Size(90, 60), maxLines: 2));
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text(word)).style!.fontSize, 14);
    expect(lineCount(tester, word), 1);
    expect(paragraph(tester, word).didExceedMaxLines, isTrue);
    expect(tester.getSize(find.text(word)).width, lessThanOrEqualTo(90));
  });

  testWidgets('a hyphenated name is one word: never wrapped at the hyphen', (
    tester,
  ) async {
    const name = 'Hans-Joachim';
    await tester.pumpWidget(sized(name, const Size(50, 60), maxLines: 2));
    expect(tester.takeException(), isNull);
    expect(lineCount(tester, name), 1);
  });

  testWidgets('two words still wrap at the space', (tester) async {
    const name = 'Krombacher alkoholfrei';
    await tester.pumpWidget(sized(name, const Size(120, 70), maxLines: 2));
    expect(tester.takeException(), isNull);
    expect(lineCount(tester, name), 2);
    expect(paragraph(tester, name).didExceedMaxLines, isFalse);
  });
}
