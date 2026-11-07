import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design.dart';
import 'chalk_board.dart';

/// The paper of the pinned note.
const Color kChalkNotePaper = Color(0xFFF5ECD2);

/// Pencil on the pinned note.
const Color kChalkNoteInk = Color(0xFF2F2A20);

/// The near-black board of the screensaver.
const Color kChalkSaverBoard = Color(0xFF0D0F0E);

/// Chalk rubbed thin, for the screensaver hint.
const Color kChalkFaint = Color(0x8CF4F1E8);

/// Caveat in [size]; a variable font, so the weight needs its variation.
TextStyle chalkStyle(
  DesignTokens tokens,
  double size, {
  Color? color,
  double height = 1.1,
}) => TextStyle(
  fontFamily: tokens.displayFont,
  fontSize: size,
  height: height,
  color: color ?? tokens.text,
  fontWeight: FontWeight.w700,
  fontVariations: const [FontVariation('wght', 700)],
);

/// A slate strip in a thin wooden frame, as high as its [child]; the grain
/// is painted once.
class ChalkStrip extends StatelessWidget {
  const ChalkStrip({required this.child, super.key});

  static const double frameWidth = 6;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.frame,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(frameWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.4),
              radius: 2.5,
              colors: [tokens.backgroundHighlight, tokens.background],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: SlateGrainPainter()),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// A hand-drawn chalk box around [child]: dashed, or a solid line; tappable
/// when [onTap] is given.
class ChalkBox extends StatelessWidget {
  const ChalkBox({
    required this.color,
    required this.child,
    this.dashed = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    super.key,
  });

  final Color color;
  final bool dashed;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ChalkBorderPainter(color: color, width: 2.5, dashed: dashed),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const RoundedRectangleBorder(
            borderRadius: kChalkCorners,
          ),
          child: Padding(
            padding: padding,
            child: Center(widthFactor: 1, heightFactor: 1, child: child),
          ),
        ),
      ),
    );
  }
}

/// A paper note pinned with a red pin, slightly rotated.
class ChalkNote extends StatelessWidget {
  const ChalkNote({required this.child, super.key});

  static const double _pin = 18;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -1.5 * math.pi / 180,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: _pin / 2),
            child: Material(
              color: kChalkNotePaper,
              elevation: 6,
              borderRadius: BorderRadius.circular(2),
              child: child,
            ),
          ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: CustomPaint(
                size: Size.square(_pin),
                painter: ChalkPinPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The red pin's head with a small highlight.
class ChalkPinPainter extends CustomPainter {
  const ChalkPinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas
      ..drawCircle(
        c + const Offset(0, 2),
        r,
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      )
      ..drawCircle(c, r, Paint()..color = const Color(0xFFC0392B))
      ..drawCircle(
        c - Offset(r * 0.35, r * 0.35),
        r * 0.3,
        Paint()..color = const Color(0x66FFFFFF),
      );
  }

  @override
  bool shouldRepaint(ChalkPinPainter old) => false;
}

/// A hand-drawn chalk circle in the middle of its box: slightly uneven and
/// not quite closed. The wobble is fixed, so is every paint.
class ChalkCirclePainter extends CustomPainter {
  const ChalkCirclePainter({required this.color, this.width = 2.2});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - width;
    final path = Path();
    const steps = 48;
    // From just past the top round to a little over the start.
    for (var i = 0; i <= steps; i++) {
      final t = -math.pi / 2 + 0.2 + i * (2 * math.pi + 0.15) / steps;
      final wobble = 1 + 0.035 * math.sin(3 * t + 0.6) + 0.02 * math.cos(5 * t);
      final p = c + Offset(math.cos(t), math.sin(t)) * (r * wobble);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(ChalkCirclePainter old) =>
      old.color != color || old.width != width;
}

/// A beer glass with a handle and a foam crown, drawn in chalk.
class ChalkBeerGlassPainter extends CustomPainter {
  const ChalkBeerGlassPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 42 × 52 grid, scaled to the box.
    final s = math.min(size.width / 42, size.height / 52);
    canvas.scale(s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final glass = Path()
      ..moveTo(6, 10)
      ..lineTo(10, 48)
      ..lineTo(30, 48)
      ..lineTo(34, 10)
      ..close();
    final handle = Path()
      ..moveTo(34, 18)
      ..lineTo(38, 18)
      ..arcToPoint(const Offset(41, 21), radius: const Radius.circular(3))
      ..lineTo(41, 31)
      ..arcToPoint(const Offset(38, 34), radius: const Radius.circular(3))
      ..lineTo(33, 34);
    final foam = Path()
      ..moveTo(5, 10)
      ..cubicTo(8, 4, 14, 4, 16, 8)
      ..cubicTo(19, 3, 26, 3, 28, 8)
      ..cubicTo(31, 5, 35, 7, 35, 10);
    canvas
      ..drawPath(glass, paint)
      ..drawPath(handle, paint)
      ..drawPath(foam, paint);
  }

  @override
  bool shouldRepaint(ChalkBeerGlassPainter old) => old.color != color;
}
