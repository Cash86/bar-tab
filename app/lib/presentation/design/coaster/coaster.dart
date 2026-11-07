import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../coaster_text.dart';
import '../design.dart';

/// Dark brown print on the cream coasters.
const Color kCoasterInk = Color(0xFF3A2414);

/// Names on coasters never shrink below this.
const double kCoasterMinFontSize = 10;

/// The lighter cream of highlighted coasters and of the hub's inner line.
const Color kCoasterPaper = Color(0xFFFFF6E6);

/// One beer coaster: a cream disc with a coloured ring, the name (and an
/// optional [subLabel], e.g. the price) in slab serif, a gold rim and a ★
/// when [highlighted], and a badge with the pending [quantity].
class Coaster extends StatelessWidget {
  const Coaster({
    required this.label,
    required this.diameter,
    required this.ring,
    this.highlighted = false,
    this.quantity = 0,
    this.onTap,
    this.subLabel,
    super.key,
  });

  final String label;
  final double diameter;
  final Color ring;
  final bool highlighted;
  final int quantity;
  final VoidCallback? onTap;
  final String? subLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final face = highlighted ? kCoasterPaper : tokens.surface;
    final d = diameter;
    return SizedBox.square(
      dimension: d,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CoasterPainter(
                face: face,
                ring: ring,
                highlighted: highlighted,
                picked: quantity > 0,
                highlight: tokens.highlight,
              ),
            ),
          ),
          Positioned.fill(
            child: _Memo(
              keys: [label, subLabel, d, ring, face, tokens.displayFont],
              builder: () => _label(tokens, face),
            ),
          ),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, customBorder: const CircleBorder()),
            ),
          ),
          if (quantity > 0)
            Positioned(
              top: -0.06 * d,
              right: -0.06 * d,
              child: IgnorePointer(child: _Badge(quantity, size: _badge(d))),
            ),
        ],
      ),
    );
  }

  static double _badge(double d) => math.max(22, 0.3 * d);

  Widget _label(DesignTokens tokens, Color face) {
    final d = diameter;
    final name = TextStyle(
      fontFamily: tokens.displayFont,
      fontSize: 0.2 * d,
      height: 1,
      color: kCoasterInk,
    );
    final sub = subLabel;
    if (sub == null) {
      return Center(
        child: CoasterText(
          label,
          diameter: d,
          style: name,
          minFontSize: kCoasterMinFontSize,
          strokeColor: face,
        ),
      );
    }
    // The whole coaster's text box, raised above the price; two lines at
    // most so the name stays clear of it.
    final nameBox = d;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The name a little above the middle, the price below it.
        Positioned(
          left: (d - nameBox) / 2,
          top: 0.4 * d - nameBox / 2,
          width: nameBox,
          height: nameBox,
          child: CoasterText(
            label,
            diameter: nameBox,
            style: name,
            minFontSize: kCoasterMinFontSize,
            maxLines: 2,
            strokeColor: face,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0.71 * d,
          height: 0.16 * d,
          child: Center(
            child: Text(
              sub,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: tokens.bodyFont,
                fontSize: 0.15 * d,
                height: 1,
                fontWeight: FontWeight.w800,
                // Darker than the ring so light group colours stay legible.
                color: Color.lerp(ring, Colors.black, 0.25),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The large hub coaster of a drink group: a disc in the group [color]
/// with the group name.
class CoasterHub extends StatelessWidget {
  const CoasterHub({
    required this.label,
    required this.diameter,
    required this.color,
    super.key,
  });

  final String label;
  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return SizedBox.square(
      dimension: diameter,
      child: CustomPaint(
        painter: _HubPainter(color),
        child: _Memo(
          keys: [label, diameter, color, tokens.displayFont],
          builder: () => Center(
            child: CoasterText(
              label,
              diameter: diameter,
              style: TextStyle(
                fontFamily: tokens.displayFont,
                fontSize: 0.17 * diameter,
                height: 1,
                color: kCoasterPaper,
              ),
              minFontSize: kCoasterMinFontSize,
              // Inside the hub's inner line: no word crosses its rim.
              wordShare: 0.85,
              strokeColor: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds its child once and hands back the same widget while [keys] stay
/// equal, so a rebuilt board (e.g. every second of the order countdown)
/// does not fit the coaster names again.
class _Memo extends StatefulWidget {
  const _Memo({required this.keys, required this.builder});

  final List<Object?> keys;
  final Widget Function() builder;

  @override
  State<_Memo> createState() => _MemoState();
}

class _MemoState extends State<_Memo> {
  Widget? _child;

  @override
  void didUpdateWidget(_Memo old) {
    super.didUpdateWidget(old);
    final a = old.keys;
    final b = widget.keys;
    var same = a.length == b.length;
    for (var i = 0; same && i < a.length; i++) {
      same = a[i] == b[i];
    }
    if (!same) _child = null;
  }

  @override
  Widget build(BuildContext context) => _child ??= widget.builder();
}

class _Badge extends StatelessWidget {
  const _Badge(this.quantity, {required this.size});

  final int quantity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: size * 0.2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.accent,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: kCoasterPaper, width: 1.5),
      ),
      child: Text(
        '$quantity',
        style: TextStyle(
          fontFamily: tokens.bodyFont,
          fontSize: size * 0.62,
          height: 1,
          fontWeight: FontWeight.w800,
          color: tokens.onAccent,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A soft shadow under a disc of [radius] around [c].
void _shadow(Canvas canvas, Offset c, double radius, double d) {
  canvas.drawCircle(
    c + Offset(0, 0.035 * d),
    radius,
    Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.04 * d),
  );
}

Paint _stroke(Color color, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..color = color;

class _CoasterPainter extends CustomPainter {
  const _CoasterPainter({
    required this.face,
    required this.ring,
    required this.highlighted,
    required this.picked,
    required this.highlight,
  });

  final Color face;
  final Color ring;
  final bool highlighted;
  final bool picked;

  /// The gold rim and ★ of a highlighted coaster.
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final r = d / 2;
    final c = size.center(Offset.zero);
    _shadow(canvas, c, r, d);
    if (picked) {
      // A light outline around a coaster that is in the order.
      canvas.drawCircle(c, r + 1.5, _stroke(kCoasterPaper, 3));
    }
    canvas.drawCircle(c, r, Paint()..color = face);
    if (!highlighted) {
      final w = math.max(2.0, 0.036 * d);
      canvas.drawCircle(c, r - 0.054 * d - w / 2, _stroke(ring, w));
      return;
    }
    // Highlighted: a broad ring with a gold rim inside it, and a ★.
    final w = 0.053 * d;
    canvas.drawCircle(c, r - 0.043 * d - w / 2, _stroke(ring, w));
    final gold = 0.021 * d;
    canvas.drawCircle(c, r - 0.096 * d - gold / 2, _stroke(highlight, gold));
    _star(canvas, Offset(c.dx, 0.17 * d), 0.055 * d, highlight);
  }

  @override
  bool shouldRepaint(_CoasterPainter old) =>
      old.face != face ||
      old.ring != ring ||
      old.highlighted != highlighted ||
      old.picked != picked ||
      old.highlight != highlight;
}

/// A five-pointed star; painted because the fonts' ★ cannot be relied on.
void _star(Canvas canvas, Offset c, double outer, Color color) {
  final inner = outer * 0.42;
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / 5;
    final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(path..close(), Paint()..color = color);
}

class _HubPainter extends CustomPainter {
  const _HubPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final r = d / 2;
    final c = size.center(Offset.zero);
    _shadow(canvas, c, r, d);
    canvas.drawCircle(c, r, Paint()..color = color);
    final w = math.max(1.5, 0.026 * d);
    canvas.drawCircle(c, r - 0.05 * d - w / 2, _stroke(kCoasterPaper, w));
  }

  @override
  bool shouldRepaint(_HubPainter old) => old.color != color;
}
