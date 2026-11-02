import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

/// One drink: name and this person's price; filled with the group colour
/// and showing a count badge once it is in the order.
class DrinkTile extends StatelessWidget {
  const DrinkTile({
    required this.name,
    required this.priceCents,
    required this.color,
    required this.quantity,
    required this.onTap,
    super.key,
  });

  static const double height = 88;

  final String name;
  final int priceCents;
  final Color color;
  final int quantity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picked = quantity > 0;
    final foreground = picked ? BarTabTheme.bottle : BarTabTheme.paper;
    return SizedBox(
      height: height,
      child: Material(
        color: picked ? color : BarTabTheme.bottle2,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                left: 14,
                top: 0,
                width: 30,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: picked ? BarTabTheme.bottle : color,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(4),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 19,
                        height: 1.08,
                        fontVariations: const [
                          FontVariation('wdth', 78),
                          FontVariation('wght', 650),
                        ],
                      ),
                    ),
                    Text(
                      formatCents(priceCents),
                      style: TextStyle(
                        color: picked ? BarTabTheme.bottle : BarTabTheme.muted,
                        fontSize: 15,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (picked)
                Positioned(
                  right: 9,
                  bottom: 9,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 33),
                    height: 33,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BarTabTheme.bottle,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Text(
                      '$quantity',
                      style: const TextStyle(
                        color: BarTabTheme.paper,
                        fontSize: 19,
                        fontVariations: [FontVariation('wght', 800)],
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
