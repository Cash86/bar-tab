import 'package:flutter/material.dart';

import 'text_fit.dart';

/// The largest size from [style]'s size down to [minFontSize] at which
/// [text] fits [box] in up to [maxLines] lines without breaking a word;
/// [minFontSize] when none does. [style] must be complete (merged into the
/// default text style), as [Text] paints it.
double fitChalkFontSize(
  String text,
  TextStyle style,
  Size box, {
  double minFontSize = 14,
  int maxLines = 1,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final base = style.fontSize ?? 14;
  bool fits(double size) {
    TextPainter paint(String text, {int? maxLines}) => TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: box.width);
    final p = paint(text, maxLines: maxLines);
    var ok = !p.didExceedMaxLines && p.height <= box.height;
    p.dispose();
    // A word wider than the box would be broken inside the word.
    for (final word in text.trim().split(RegExp(r'\s+'))) {
      if (!ok) break;
      final wp = paint(word, maxLines: 1);
      ok = !wp.didExceedMaxLines;
      wp.dispose();
    }
    return ok;
  }

  return largestFittingFontSize(
    minFontSize < base ? minFontSize : base,
    base,
    fits,
  );
}

/// Text that shrinks from its style's size down to [minFontSize] to fit the
/// box it is given, and is cut with `…` when even that is too large.
class ChalkText extends StatelessWidget {
  const ChalkText(
    this.text, {
    super.key,
    required this.style,
    this.minFontSize = 14,
    this.maxLines = 1,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final double minFontSize;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Measure what Text paints: the style merged into the default one.
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = fitChalkFontSize(
          text,
          style,
          constraints.biggest,
          minFontSize: minFontSize,
          maxLines: maxLines,
          textScaler: scaler,
          textDirection: direction,
        );
        return Text(
          text,
          style: style.copyWith(fontSize: size),
          textScaler: scaler,
          maxLines: maxLines,
          textAlign: textAlign,
          softWrap: maxLines > 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
