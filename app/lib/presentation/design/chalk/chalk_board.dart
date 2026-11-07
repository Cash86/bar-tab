import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design.dart';

/// Width of the wooden frame around the board.
const double kChalkFrameWidth = 10;

/// Slightly uneven corners, like a hand-drawn chalk line.
const BorderRadius kChalkCorners = BorderRadius.only(
  topLeft: Radius.circular(14),
  topRight: Radius.circular(6),
  bottomRight: Radius.circular(16),
  bottomLeft: Radius.circular(8),
);

/// A slate board in a wooden frame behind [child]; the grain is painted once.
class ChalkBoard extends StatelessWidget {
  const ChalkBoard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.frame,
        border: Border.all(
          color: Color.lerp(tokens.frame, Colors.black, 0.35)!,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(kChalkFrameWidth - 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.2),
              radius: 1.1,
              colors: [tokens.backgroundHighlight, tokens.background],
            ),
            border: Border.all(
              color: Color.lerp(tokens.frame, Colors.black, 0.45)!,
              width: 2,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const RepaintBoundary(
                child: CustomPaint(painter: _SlateGrainPainter()),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Faint diagonal grain and chalk dust, seeded so every paint is the same.
class _SlateGrainPainter extends CustomPainter {
  const _SlateGrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grain = Paint()
      ..color = const Color(0x06FFFFFF)
      ..strokeWidth = 3;
    // 115° grain: lines running down to the left, 7 px apart.
    final dx = size.height * math.tan(25 * math.pi / 180);
    for (var x = -dx; x < size.width + dx; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(x - dx, size.height), grain);
    }
    final random = math.Random(7);
    final dust = Paint()..color = const Color(0x0DF4F1E8);
    final count = (size.width * size.height / 900).round();
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        0.5 + random.nextDouble(),
        dust,
      );
    }
  }

  @override
  bool shouldRepaint(_SlateGrainPainter oldDelegate) => false;
}

/// A chalk line around a box with [kChalkCorners]; dashed or solid.
class ChalkBorderPainter extends CustomPainter {
  const ChalkBorderPainter({
    required this.color,
    this.width = 2,
    this.dashed = false,
    this.fill,
  });

  final Color color;
  final double width;
  final bool dashed;

  /// Painted inside the line, e.g. a picked box.
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = kChalkCorners.toRRect(
      (Offset.zero & size).deflate(width / 2),
    );
    if (fill case final fill?) {
      canvas.drawRRect(rrect, Paint()..color = fill);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final path = Path()..addRRect(rrect);
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    // Uneven dashes read as chalk; the pattern is fixed, so is every paint.
    const pattern = [9.0, 4.0, 6.0, 3.0, 11.0, 5.0];
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      var i = 0;
      while (d < metric.length) {
        final dash = pattern[i % pattern.length];
        final gap = pattern[(i + 1) % pattern.length];
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
        i += 2;
      }
    }
  }

  @override
  bool shouldRepaint(ChalkBorderPainter old) =>
      old.color != color ||
      old.width != width ||
      old.dashed != dashed ||
      old.fill != fill;
}
