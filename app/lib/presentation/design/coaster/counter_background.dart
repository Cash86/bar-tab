import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../design.dart';

/// The green bar counter behind [child]: a dark green radial gradient with
/// a fine speckle that is painted once.
class CounterBackground extends StatelessWidget {
  const CounterBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.1,
          colors: [tokens.backgroundHighlight, tokens.background],
          stops: const [0, 0.8],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _SpecklePainter())),
          child,
        ],
      ),
    );
  }
}

/// Faint light specks like a worn counter top, seeded so every paint is
/// the same.
class _SpecklePainter extends CustomPainter {
  const _SpecklePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(11);
    // About one speck per 7×7 px cell, drawn as two point batches.
    final count = (size.width * size.height / 49).round();
    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < count; i++) {
      (i.isEven ? light : dark).add(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
      );
    }
    Paint specks(Color color) => Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawPoints(PointMode.points, light, specks(const Color(0x0DFFFFFF)))
      ..drawPoints(PointMode.points, dark, specks(const Color(0x14000000)));
  }

  @override
  bool shouldRepaint(_SpecklePainter old) => false;
}
