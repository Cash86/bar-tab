import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/order.dart';
import '../../l10n/app_localizations.dart';
import '../format.dart';
import '../theme.dart';
import 'order_controller.dart';

/// "2× Apfelschorle, 1× Augustiner Hell" in first-tap order.
String orderSummary(AppLocalizations l10n, OrderDraft draft, Catalog? catalog) {
  final names = {for (final d in catalog?.drinks ?? const <Drink>[]) d.id: d};
  return draft.lines
      .map((l) => l10n.orderLine(l.quantity, names[l.drinkId]?.name ?? '?'))
      .join(', ');
}

/// The pending order: lines, total, countdown, discard and done.
class OrderBar extends StatelessWidget {
  const OrderBar({
    required this.summary,
    required this.totalCents,
    required this.secondsLeft,
    required this.onDiscard,
    this.saveFailed = false,
    required this.onDone,
    super.key,
  });

  final String summary;
  final int totalCents;
  final int secondsLeft;

  /// Shows the retry hint instead of the countdown.
  final bool saveFailed;
  final VoidCallback onDiscard;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const text = BarTabTheme.bottle;
    final delay = kAutoBookDelay.inSeconds;
    return Material(
      color: BarTabTheme.paper,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 14, 18, 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: text,
                          fontSize: 23,
                          fontVariations: [FontVariation('wght', 700)],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        saveFailed
                            ? l10n.orderBarRetrying
                            : l10n.orderBarCountdown(secondsLeft),
                        style: const TextStyle(color: text, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Text(
                  formatCents(totalCents),
                  style: const TextStyle(
                    color: text,
                    fontSize: 28,
                    fontVariations: [FontVariation('wght', 800)],
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 20),
                OrderButton(
                  label: l10n.orderBarDiscard,
                  solid: false,
                  onTap: onDiscard,
                ),
                const SizedBox(width: 12),
                OrderButton(
                  label: l10n.orderBarDone,
                  solid: true,
                  onTap: onDone,
                ),
              ],
            ),
          ),
          // Drains towards the auto-booking, one step per second.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 6,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(seconds: 1),
              alignment: Alignment.centerLeft,
              widthFactor: ((secondsLeft - 1) / delay).clamp(0.0, 1.0),
              child: const ColoredBox(color: text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined (ghost) or filled button on paper.
class OrderButton extends StatelessWidget {
  const OrderButton({
    required this.label,
    required this.solid,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool solid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const text = BarTabTheme.bottle;
    return Material(
      color: solid ? text : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: solid
            ? BorderSide.none
            : const BorderSide(color: text, width: 2.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: solid ? BarTabTheme.paper : text,
              fontSize: 20,
              fontVariations: const [FontVariation('wght', 700)],
            ),
          ),
        ),
      ),
    );
  }
}
