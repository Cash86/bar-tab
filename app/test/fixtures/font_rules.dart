import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks every [Text] on screen against the bundled fonts' rules: Caveat is
/// variable, so a weight needs the matching `wght` variation; Alfa Slab One
/// has a single face, so a weight above w400 would be faked.
void expectFontRules(WidgetTester tester) {
  for (final element in find.byType(Text).evaluate()) {
    final text = element.widget as Text;
    final style = DefaultTextStyle.of(element).style.merge(text.style);
    final label = text.data ?? '$text';
    switch (style.fontFamily) {
      case 'Caveat':
        final wght = style.fontVariations
            ?.where((v) => v.axis == 'wght')
            .firstOrNull;
        expect(wght, isNotNull, reason: '$label: Caveat needs wght');
        expect(
          style.fontWeight?.value,
          wght!.value.round(),
          reason: '$label: fontWeight and wght must match',
        );
      case 'Alfa Slab One':
        expect(
          (style.fontWeight ?? FontWeight.w400).value,
          lessThanOrEqualTo(400),
          reason: '$label: Alfa Slab One has no bold face',
        );
    }
  }
}
