import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import 'drink_tile.dart';

/// One row of equal-width tiles with the person's favourite drinks; a tap
/// books one unit. Inert while [enabled] is false; greyed out while
/// [dimmed] (a pending grid order or an open sheet, not a running commit,
/// which would only flicker).
class QuickBar extends StatelessWidget {
  const QuickBar({
    required this.drinks,
    required this.priceOf,
    required this.colorOf,
    required this.enabled,
    required this.dimmed,
    required this.onTap,
    super.key,
  });

  final List<Drink> drinks;
  final int Function(Drink) priceOf;
  final Color Function(Drink) colorOf;
  final bool enabled;
  final bool dimmed;
  final void Function(Drink drink, int priceCents) onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: dimmed ? 0.35 : 1,
        child: Row(
          children: [
            for (var i = 0; i < drinks.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: DrinkTile(
                  key: ValueKey('quick-${drinks[i].id}'),
                  name: drinks[i].name,
                  priceCents: priceOf(drinks[i]),
                  color: colorOf(drinks[i]),
                  quantity: 0,
                  onTap: () => onTap(drinks[i], priceOf(drinks[i])),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
