import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design.dart';
import 'coaster.dart';

/// Till roll paper.
const Color kReceiptPaper = Color(0xFFFFFDF6);

/// Print on the till receipt.
const Color kReceiptInk = Color(0xFF333333);

/// Height of the receipt's torn zigzag edge.
const double kReceiptZigzag = 8;

/// Monospace till print; the platform's monospace face.
TextStyle receiptStyle(double size, {Color color = kReceiptInk}) => TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: const ['Barlow Condensed'],
  fontSize: size,
  height: 1.2,
  color: color,
  fontWeight: FontWeight.w700,
);

/// Barlow Condensed, a family of static faces picked by [weight].
TextStyle coasterBodyStyle(
  DesignTokens tokens,
  double size, {
  Color color = kCoasterInk,
  FontWeight weight = FontWeight.w700,
}) => TextStyle(
  fontFamily: tokens.bodyFont,
  fontSize: size,
  height: 1.1,
  color: color,
  fontWeight: weight,
);

/// Alfa Slab One: a single face, so no weight is ever set.
TextStyle coasterDisplayStyle(
  DesignTokens tokens,
  double size, {
  Color color = kCoasterInk,
}) => TextStyle(
  fontFamily: tokens.displayFont,
  fontSize: size,
  height: 1.05,
  color: color,
  // Set, so no inherited bold is faked.
  fontWeight: FontWeight.w400,
);

/// A till receipt behind [child], with a zigzag torn bottom edge.
class TillReceipt extends StatelessWidget {
  const TillReceipt({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _ReceiptPainter(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: kReceiptZigzag),
        child: child,
      ),
    );
  }
}

class _ReceiptPainter extends CustomPainter {
  const _ReceiptPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tooth = 14.0;
    final body = size.height - kReceiptZigzag;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, body);
    // Teeth from right to left, ending on the left edge.
    final n = math.max(1, (size.width / tooth).round());
    final w = size.width / n;
    for (var i = n; i > 0; i--) {
      path
        ..lineTo((i - 0.5) * w, size.height)
        ..lineTo((i - 1) * w, body);
    }
    path.close();
    canvas
      ..drawShadow(path, const Color(0xFF000000), 5, false)
      ..drawPath(path, Paint()..color = kReceiptPaper);
  }

  @override
  bool shouldRepaint(_ReceiptPainter old) => false;
}

/// Slides [child] in from above its place once, when it first shows.
class SlideInFromTop extends StatefulWidget {
  const SlideInFromTop({required this.child, super.key});

  final Widget child;

  @override
  State<SlideInFromTop> createState() => _SlideInFromTopState();
}

class _SlideInFromTopState extends State<SlideInFromTop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  late final Animation<Offset> _offset = Tween(
    begin: const Offset(0, -1.1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SlideTransition(position: _offset, child: widget.child);
}

/// A flat button on the counter: dark red when [primary], else cream.
class CoasterButton extends StatelessWidget {
  const CoasterButton({
    required this.label,
    required this.primary,
    required this.onTap,
    this.fontSize = 20,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    super.key,
  });

  final String label;
  final bool primary;
  final VoidCallback? onTap;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Material(
      color: primary ? tokens.accent : tokens.surface,
      borderRadius: BorderRadius.circular(4),
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: coasterBodyStyle(
              tokens,
              fontSize,
              color: primary ? tokens.onAccent : kCoasterInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// The large coaster of the quantity sheet: a cream disc with a ring in
/// [ring], carrying [child] in its middle.
class SheetCoaster extends StatelessWidget {
  const SheetCoaster({
    required this.diameter,
    required this.ring,
    required this.child,
    super.key,
  });

  final double diameter;
  final Color ring;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return SizedBox.square(
      dimension: diameter,
      child: CustomPaint(
        painter: _DiscPainter(face: tokens.surface, ring: ring),
        child: Center(child: child),
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  const _DiscPainter({required this.face, required this.ring});

  final Color face;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas
      ..drawCircle(
        c + const Offset(0, 8),
        r,
        Paint()
          ..color = const Color(0x8C000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..drawCircle(c, r, Paint()..color = face)
      ..drawCircle(
        c,
        r - 12,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.face != face || old.ring != ring;
}

/// The screensaver's dimmed coaster with [label], turned by [turns].
class SaverCoaster extends StatelessWidget {
  const SaverCoaster({
    required this.label,
    required this.turns,
    this.diameter = 170,
    super.key,
  });

  final String label;

  /// Rotation in full turns.
  final double turns;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Transform.rotate(
      angle: turns * 2 * math.pi,
      child: SizedBox.square(
        dimension: diameter,
        child: CustomPaint(
          painter: const _SaverCoasterPainter(),
          child: Padding(
            padding: EdgeInsets.all(diameter * 0.16),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: coasterDisplayStyle(
                  tokens,
                  diameter * 0.12,
                  color: const Color(0xFF1D1A14),
                ).copyWith(decoration: TextDecoration.none),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SaverCoasterPainter extends CustomPainter {
  const _SaverCoasterPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas
      ..drawCircle(c, r, Paint()..color = const Color(0xFF7D7462))
      ..drawCircle(
        c,
        r - 0.06 * size.shortestSide,
        Paint()
          ..color = const Color(0xFF3D5A4C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
  }

  @override
  bool shouldRepaint(_SaverCoasterPainter old) => false;
}
