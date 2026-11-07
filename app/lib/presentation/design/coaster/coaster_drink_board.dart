import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/catalog.dart';
import '../../../l10n/app_localizations.dart';
import '../../drinks/drink_board_data.dart';
import '../../drinks/order_bar.dart';
import '../../format.dart';
import '../coaster_plan.dart';
import '../design.dart';
import 'coaster.dart';

/// Width of the "Dein Tablett" serving tray.
const double kCoasterTrayWidth = 236;

/// Space between the tray and the ring blocks.
const double kCoasterTrayGap = 22;

/// Free space below the rings so the order bar never covers a coaster; kept
/// even without an order, so the board does not jump on the first tap.
const double kCoasterOrderBarRoom = OrderBar.height + kOrderBarBottom + 6;

/// Fixed turns of the favourites on the tray, in degrees.
const _turns = [-5.0, 4.0, -3.0, 6.0];

/// The Bierdeckel drink selection: the serving tray with the favourites on
/// the left, one ring block per group on the right (see [planCoasterBoard]).
class CoasterDrinkBoard extends StatelessWidget {
  const CoasterDrinkBoard(this.data, {super.key});

  final DrinkBoardData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.favourites.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 14),
            child: SizedBox(
              width: kCoasterTrayWidth,
              child: _Tray(data, key: const ValueKey('coaster-tray')),
            ),
          ),
          const SizedBox(width: kCoasterTrayGap),
        ],
        Expanded(child: _Rings(data)),
      ],
    );
  }
}

class _Rings extends StatelessWidget {
  const _Rings(this.data);

  final DrinkBoardData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(
          constraints.maxWidth,
          math.max(0, constraints.maxHeight - kCoasterOrderBarRoom),
        );
        final plan = planCoasterBoard([
          for (final (_, drinks) in data.groups) drinks.length,
        ], area);
        final height = plan.scrolls
            ? plan.blocks.fold<double>(0, (h, b) => math.max(h, b.bottom))
            : area.height;
        final board = SizedBox(
          width: area.width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < plan.blocks.length; i++)
                Positioned.fromRect(
                  rect: plan.blocks[i],
                  child: _RingBlock(
                    key: ValueKey('coaster-block-${data.groups[i].$1.id}'),
                    group: data.groups[i].$1,
                    drinks: data.groups[i].$2,
                    rings: plan.groups[i],
                    data: data,
                  ),
                ),
            ],
          ),
        );
        if (!plan.scrolls) {
          return Align(alignment: Alignment.topLeft, child: board);
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: kCoasterOrderBarRoom),
          child: board,
        );
      },
    );
  }
}

/// One group: the hub in the group colour, its drinks evenly spread on the
/// rings around it, inner ring first.
class _RingBlock extends StatelessWidget {
  const _RingBlock({
    super.key,
    required this.group,
    required this.drinks,
    required this.rings,
    required this.data,
  });

  final DrinkGroup group;
  final List<Drink> drinks;
  final GroupRings rings;
  final DrinkBoardData data;

  @override
  Widget build(BuildContext context) {
    final color = Color(group.color);
    final size = rings.footprint;
    final c = size.center(Offset.zero);
    final coaster = rings.coaster;
    final children = <Widget>[
      Positioned(
        left: c.dx - rings.hub / 2,
        top: c.dy - rings.hub / 2,
        child: CoasterHub(
          key: ValueKey('coaster-hub-${group.id}'),
          label: group.name,
          diameter: rings.hub,
          color: color,
        ),
      ),
    ];
    var next = 0;
    for (var k = 0; k < rings.rings.length; k++) {
      final ring = rings.rings[k];
      final step = 2 * math.pi / ring.count;
      // Outer rings start half a step on, between the inner coasters.
      final start = -math.pi / 2 + (k.isOdd ? step / 2 : 0);
      for (var i = 0; i < ring.count && next < drinks.length; i++) {
        final drink = drinks[next++];
        final a = start + i * step;
        final p = c + Offset(math.cos(a), math.sin(a)) * ring.radius;
        final price = data.priceOf(drink);
        children.add(
          Positioned(
            left: p.dx - coaster / 2,
            top: p.dy - coaster / 2,
            child: Coaster(
              key: ValueKey('drink-${drink.id}'),
              label: drink.name,
              subLabel: formatCents(price),
              diameter: coaster,
              ring: color,
              quantity: data.quantities[drink.id] ?? 0,
              onTap: () => data.onTap(drink, price),
            ),
          ),
        );
      }
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }
}

/// The silver serving tray: "Dein Tablett" and up to four large
/// gold-rimmed coasters, each slightly turned; inert and dimmed like
/// Standard's quick bar.
class _Tray extends StatelessWidget {
  const _Tray(this.data, {super.key});

  final DrinkBoardData data;

  static const _slots = 4;
  static const _slotGap = 12.0;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return IgnorePointer(
      ignoring: !data.favouritesEnabled,
      child: Opacity(
        opacity: data.favouritesDimmed ? 0.35 : 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(child: CustomPaint(painter: _TrayPainter())),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      AppLocalizations.of(context).favouritesTray.toUpperCase(),
                      style: TextStyle(
                        fontFamily: tokens.bodyFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.2,
                        color: const Color(0xFF3B4248),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Sized for four: fewer favourites keep the size and
                        // spread out.
                        final fit =
                            (constraints.maxHeight - (_slots - 1) * _slotGap) /
                            _slots;
                        final diameter = math.max(
                          44.0,
                          math.min(fit, math.min(124.0, constraints.maxWidth)),
                        );
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (var i = 0; i < data.favourites.length; i++)
                              _favourite(tokens, i, diameter),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _favourite(DesignTokens tokens, int i, double diameter) {
    final drink = data.favourites[i];
    final price = data.priceOf(drink);
    return Transform.rotate(
      angle: _turns[i % _turns.length] * math.pi / 180,
      child: Coaster(
        key: ValueKey('quick-${drink.id}'),
        label: drink.name,
        subLabel: formatCents(price),
        diameter: diameter,
        ring: tokens.accent,
        highlighted: true,
        onTap: () => data.onFavouriteTap(drink, price),
      ),
    );
  }
}

/// A brushed silver tray seen from above, with a raised rim.
class _TrayPainter extends CustomPainter {
  const _TrayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.elliptical(size.width / 2, size.height * 0.18),
    );
    canvas.drawRRect(
      shape.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.24, -0.5),
          radius: 1.1,
          colors: [
            Color(0xFFF4F6F8),
            Color(0xFFC3CAD0),
            Color(0xFF8D969E),
            Color(0xFF6B737A),
          ],
          stops: [0, 0.35, 0.75, 1],
        ).createShader(rect),
    );
    Paint rim(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    canvas
      ..drawRRect(shape.deflate(3), rim(const Color(0xFFB9C1C8), 6))
      ..drawRRect(shape.deflate(7), rim(const Color(0xFF7C858D), 2));
  }

  @override
  bool shouldRepaint(_TrayPainter old) => false;
}
