import 'package:flutter/material.dart';

import 'coaster_text.dart';

/// Text that shrinks from its style's size down to [minFontSize] to fit the
/// box it is given, and is cut with `…` when even that is too large.
class ChalkText extends StatelessWidget {
  const ChalkText(
    this.text, {
    super.key,
    required this.style,
    this.minFontSize = 14,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle style;
  final double minFontSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Measure what Text paints: the style merged into the default one.
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = style.fontSize ?? 14;
        bool fits(double size) {
          TextPainter paint(String text, {int? maxLines}) => TextPainter(
            text: TextSpan(
              text: text,
              style: style.copyWith(fontSize: size),
            ),
            textDirection: direction,
            textScaler: scaler,
            maxLines: maxLines,
          )..layout(maxWidth: constraints.maxWidth);
          final p = paint(text, maxLines: maxLines);
          var ok = !p.didExceedMaxLines && p.height <= constraints.maxHeight;
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

        final size = largestFittingFontSize(
          minFontSize < base ? minFontSize : base,
          base,
          fits,
        );
        return Text(
          text,
          style: style.copyWith(fontSize: size),
          textScaler: scaler,
          maxLines: maxLines,
          softWrap: maxLines > 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
