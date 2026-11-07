import 'package:flutter/material.dart';

import '../../domain/app_design.dart';
import 'design.dart';

/// Share of the coaster diameter that the text must fit into (a square
/// inside the round coaster); also the line width several words wrap at.
const _innerShare = 0.78;

/// Share of the coaster diameter a word of a several-word name may take; it
/// may cross the rim.
const _wordShare = 1.15;

/// Share a single-word name may take; the outline keeps it readable over
/// the rim.
const _singleWordShare = 1.5;

const _maxLines = 3;

/// Width of the outline drawn behind every name.
const kCoasterStrokeWidth = 4.0;

/// How a name is laid out on a coaster.
@immutable
class CoasterTextFit {
  const CoasterTextFit({
    required this.fontSize,
    required this.lines,
    required this.width,
    required this.overflowsRim,
    required this.ellipsized,
  });

  final double fontSize;
  final int lines;

  /// Width of the text box: the inner square, or wider (up to the word
  /// share of the diameter) for a word that is longer than the inner square.
  final double width;

  /// The text box is wider than the coaster: a long word crosses the rim.
  final bool overflowsRim;

  /// The text did not fit even at the minimum size and is cut with `…`.
  final bool ellipsized;
}

/// Text breaks into several lines only at spaces; a hyphenated name such as
/// "Hans-Joachim" is one word.
bool _isSingleWord(String text) => !text.trim().contains(RegExp(r'\s'));

/// The largest font size in [min]..[max] for which [fits] holds; [min] when
/// none does. Assumes that a text fitting at one size fits at every smaller
/// one.
double largestFittingFontSize(
  double min,
  double max,
  bool Function(double size) fits,
) {
  if (max <= min || fits(max)) return max;
  if (!fits(min)) return min;
  var lo = min;
  var hi = max;
  for (var i = 0; i < 10; i++) {
    final mid = (lo + hi) / 2;
    if (fits(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Lays out [text] for a coaster of [diameter].
///
/// The text has to fit, in up to [maxLines] lines, into the height of the
/// inner square (`0.78 * diameter`). Several words wrap at spaces (not at
/// hyphens: "Hans-Joachim" is one word) at the inner square's width. A word
/// is never broken: one longer than the inner square widens the text box
/// and may cross the rim, up to [wordShare] of the diameter (default
/// `1.5` for a single word, `1.15` for a word among several). The size
/// shrinks from the style's size down to [minFontSize]; if the text still
/// does not fit there, it is cut with `…`: several words on the last line,
/// or, when a word alone is too wide, the whole name on one line.
CoasterTextFit fitCoasterText(
  String text,
  double diameter,
  TextStyle style, {
  double minFontSize = 9,
  int maxLines = _maxLines,
  double? wordShare,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final base = style.fontSize ?? 14;
  final min = minFontSize < base ? minFontSize : base;
  final inner = _innerShare * diameter;
  final single = _isSingleWord(text);
  final widest =
      (wordShare ?? (single ? _singleWordShare : _wordShare)) * diameter;
  final lineLimit = single ? 1 : maxLines;
  final segments = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();

  TextPainter paint(
    String text,
    double size, {
    int? maxLines,
    double maxWidth = double.infinity,
    String? ellipsis,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(fontSize: size),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    textScaler: textScaler,
    maxLines: maxLines,
    ellipsis: ellipsis,
  )..layout(maxWidth: maxWidth);

  double longestSegment(double size) {
    var longest = 0.0;
    for (final s in segments) {
      final p = paint(s, size, maxLines: 1);
      if (p.width > longest) longest = p.width;
      p.dispose();
    }
    return longest.ceilToDouble();
  }

  double boxWidth(double longest) => longest < inner
      ? inner
      : longest > widest
      ? widest
      : longest;

  bool fits(double size) {
    final longest = longestSegment(size);
    if (longest > widest) return false;
    final p = paint(
      text,
      size,
      maxLines: lineLimit,
      maxWidth: boxWidth(longest),
    );
    final ok = !p.didExceedMaxLines && p.height <= inner;
    p.dispose();
    return ok;
  }

  final size = largestFittingFontSize(min, base, fits);
  final ellipsized = !fits(size);
  final longest = longestSegment(size);
  final width = boxWidth(longest);
  // A word wider than the box would wrap in pieces: keep the name on one
  // line and cut it there. Otherwise keep as many lines as the inner square
  // holds.
  var lines = longest > widest ? 1 : lineLimit;
  late TextPainter p;
  while (true) {
    p = paint(
      text,
      size,
      maxLines: lines,
      maxWidth: width,
      ellipsis: ellipsized ? '…' : null,
    );
    if (lines == 1 || p.height <= inner) break;
    p.dispose();
    lines--;
  }
  final laidOut = p.computeLineMetrics().length;
  p.dispose();
  return CoasterTextFit(
    fontSize: size,
    lines: laidOut,
    width: width,
    overflowsRim: width > diameter,
    ellipsized: ellipsized,
  );
}

/// A name on a coaster of [diameter], laid out by [fitCoasterText] and drawn
/// twice: an outline in [strokeColor] (the coaster colour) behind the fill,
/// so text crossing the rim stays readable.
class CoasterText extends StatelessWidget {
  const CoasterText(
    this.text, {
    super.key,
    required this.diameter,
    required this.style,
    this.minFontSize = 9,
    this.maxLines = _maxLines,
    this.wordShare,
    this.strokeColor,
  });

  final String text;
  final double diameter;
  final TextStyle style;
  final double minFontSize;
  final int maxLines;

  /// See [fitCoasterText]; e.g. `0.85` keeps every word inside a hub.
  final double? wordShare;

  /// Defaults to the Bierdeckel coaster colour.
  final Color? strokeColor;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Measure what Text paints: the style merged into the default one.
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    final fit = fitCoasterText(
      text,
      diameter,
      style,
      minFontSize: minFontSize,
      maxLines: maxLines,
      wordShare: wordShare,
      textScaler: scaler,
    );
    final fill = style.copyWith(fontSize: fit.fontSize);
    final stroke = fill.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kCoasterStrokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor ?? tokensFor(AppDesign.bierdeckel).surface,
    );
    final softWrap = fit.lines > 1;
    // The outline is a plain RichText without semantics, so the name is
    // found (by finders and screen readers) once, via the fill's Text.
    final outline = ExcludeSemantics(
      child: RichText(
        text: TextSpan(text: text, style: stroke),
        textAlign: TextAlign.center,
        textScaler: scaler,
        maxLines: fit.lines,
        softWrap: softWrap,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final fillText = Text(
      text,
      style: fill,
      textAlign: TextAlign.center,
      textScaler: scaler,
      maxLines: fit.lines,
      softWrap: softWrap,
      overflow: TextOverflow.ellipsis,
    );

    return SizedBox.square(
      dimension: diameter,
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: fit.width,
        maxHeight: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [outline, fillText],
        ),
      ),
    );
  }
}
