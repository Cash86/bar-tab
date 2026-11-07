import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'text_fit.dart';

/// How often a chalk text was fitted; tests check that a rebuild with
/// unchanged inputs does not measure again.
@visibleForTesting
int debugChalkFitCount = 0;

/// How a chalk text is laid out.
@immutable
class ChalkTextFit {
  const ChalkTextFit({required this.fontSize, required this.lines});

  final double fontSize;

  /// The lines the text may take: one for a single word (a hyphenated name
  /// such as "Hans-Joachim" is one word), and one when a word is wider than
  /// the box even at the minimum size; the text is then cut with `…` on
  /// that line instead of being broken inside the word.
  final int lines;
}

/// Lays out [text] for [box]: the largest size from [style]'s size down to
/// [minFontSize] at which it fits in up to [maxLines] lines, wrapping only
/// at spaces; [minFontSize] when none does. [style] must be complete
/// (merged into the default text style), as [Text] paints it.
ChalkTextFit fitChalkText(
  String text,
  TextStyle style,
  Size box, {
  double minFontSize = 14,
  int maxLines = 1,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  debugChalkFitCount++;
  final base = style.fontSize ?? 14;
  final words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final lineLimit = words.length > 1 ? maxLines : 1;

  TextPainter paint(String text, double size, int maxLines) => TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(fontSize: size),
    ),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: maxLines,
  )..layout(maxWidth: box.width);

  // A word wider than the box would be broken inside the word.
  bool wordsFit(double size) {
    for (final word in words) {
      final p = paint(word, size, 1);
      final ok = !p.didExceedMaxLines;
      p.dispose();
      if (!ok) return false;
    }
    return true;
  }

  bool fits(double size) {
    final p = paint(text, size, lineLimit);
    final ok = !p.didExceedMaxLines && p.height <= box.height;
    p.dispose();
    return ok && wordsFit(size);
  }

  final size = largestFittingFontSize(
    minFontSize < base ? minFontSize : base,
    base,
    fits,
  );
  return ChalkTextFit(fontSize: size, lines: wordsFit(size) ? lineLimit : 1);
}

/// The font size of [fitChalkText].
double fitChalkFontSize(
  String text,
  TextStyle style,
  Size box, {
  double minFontSize = 14,
  int maxLines = 1,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) => fitChalkText(
  text,
  style,
  box,
  minFontSize: minFontSize,
  maxLines: maxLines,
  textScaler: textScaler,
  textDirection: textDirection,
).fontSize;

/// Text that shrinks from its style's size down to [minFontSize] to fit the
/// box it is given, and is cut with `…` when even that is too large (see
/// [fitChalkText]). It fits again only when its inputs change.
class ChalkText extends StatefulWidget {
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
  State<ChalkText> createState() => _ChalkTextState();
}

class _ChalkTextState extends State<ChalkText> {
  /// The last fit and what it was fitted for: the screens rebuild on every
  /// tap and every second of a countdown.
  (List<Object?>, ChalkTextFit)? _fit;

  ChalkTextFit _fitFor(
    TextStyle style,
    Size box,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final key = <Object?>[
      widget.text,
      style,
      box,
      widget.minFontSize,
      widget.maxLines,
      scaler,
      direction,
    ];
    if (_fit case (final k, final fit) when listEquals(k, key)) return fit;
    final fit = fitChalkText(
      widget.text,
      style,
      box,
      minFontSize: widget.minFontSize,
      maxLines: widget.maxLines,
      textScaler: scaler,
      textDirection: direction,
    );
    _fit = (key, fit);
    return fit;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Measure what Text paints: the style merged into the default one.
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = _fitFor(style, constraints.biggest, scaler, direction);
        return Text(
          widget.text,
          style: style.copyWith(fontSize: fit.fontSize),
          textScaler: scaler,
          maxLines: fit.lines,
          textAlign: widget.textAlign,
          softWrap: fit.lines > 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
