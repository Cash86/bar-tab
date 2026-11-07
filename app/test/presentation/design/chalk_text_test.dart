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
}
