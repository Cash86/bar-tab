import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/order.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../format.dart';
import 'order_controller.dart';

/// "2× Apfelschorle, 1× Augustiner Hell" in first-tap order.
String orderSummary(AppLocalizations l10n, OrderDraft draft, Catalog? catalog) {
  final names = {for (final d in catalog?.drinks ?? const <Drink>[]) d.id: d};
  return draft.lines
      .map((l) => l10n.orderLine(l.quantity, names[l.drinkId]?.name ?? '?'))
      .join(', ');
}

/// Distance of the order bar from the bottom of the drink screen.
const double kOrderBarBottom = 24;

/// The pending order: lines, total, countdown, discard and done.
class OrderBar extends StatelessWidget {
  const OrderBar({
    required this.summary,
    required this.totalCents,
    required this.secondsLeft,
    required this.countdownRun,
    required this.onDiscard,
    this.saveFailed = false,
    required this.onDone,
    super.key,
  });

  /// Height of the bar with one summary line, the content's height in every
  /// design's font (checked in order_bar_test.dart). The bar is never lower,
  /// so boards can keep this room before it shows.
  static const double height = 99;

  final String summary;
  final int totalCents;
  final int secondsLeft;

  /// A new value refills the countdown bar (see [OrderState.countdownRun]).
  final int countdownRun;

  /// Shows the retry hint instead of the countdown.
  final bool saveFailed;
  final VoidCallback onDiscard;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = tokens.background;
    final bar = Material(
      color: tokens.text,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 14, 18, 24),
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
                        style: TextStyle(
                          color: text,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        saveFailed
                            ? l10n.orderBarRetrying
                            : l10n.orderBarCountdown(secondsLeft),
                        style: TextStyle(color: text, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Text(
                  formatCents(totalCents),
                  style: TextStyle(
                    color: text,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    fontVariations: const [FontVariation('wght', 800)],
                    fontFeatures: const [FontFeature.tabularFigures()],
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
          // Thick and full width so it is clear the order books by itself.
          Positioned(
            key: const Key('order-bar-progress'),
            left: 0,
            right: 0,
            bottom: 0,
            height: 12,
            child: _CountdownStrip(run: countdownRun),
          ),
        ],
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: bar,
    );
  }
}

/// Starts full for every countdown run and drains continuously to empty
/// over [kAutoBookDelay], when the order books.
class _CountdownStrip extends StatefulWidget {
  const _CountdownStrip({required this.run});

  final int run;

  @override
  State<_CountdownStrip> createState() => _CountdownStripState();
}

class _CountdownStripState extends State<_CountdownStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drain = AnimationController(
    vsync: this,
    duration: kAutoBookDelay,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _drain.reverse(from: 1);
  }

  @override
  void didUpdateWidget(_CountdownStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.run != oldWidget.run) _drain.reverse(from: 1);
  }

  @override
  void dispose() {
    _drain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = DesignTokens.of(context).background;
    return ColoredBox(
      color: color.withValues(alpha: 0.15),
      child: AnimatedBuilder(
        animation: _drain,
        builder: (context, child) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: _drain.value,
          child: child,
        ),
        child: ColoredBox(color: color),
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
    final tokens = DesignTokens.of(context);
    final text = tokens.background;
    return Material(
      color: solid ? text : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: solid ? BorderSide.none : BorderSide(color: text, width: 2.5),
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
              color: solid ? tokens.text : text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
            ),
          ),
        ),
      ),
    );
  }
}
