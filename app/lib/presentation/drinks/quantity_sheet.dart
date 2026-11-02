import 'package:flutter/material.dart';

import '../../domain/order.dart';
import '../../l10n/app_localizations.dart';
import '../format.dart';
import '../theme.dart';
import 'keypad.dart';
import 'order_bar.dart';

/// Side sheet to set one drink's quantity with −/+ and an in-app keypad.
///
/// The first keypad press after opening replaces the number, later presses
/// append; the crate key also lets the next digit start fresh. The number
/// stays within 0..999.
class QuantitySheet extends StatefulWidget {
  const QuantitySheet({
    required this.drinkName,
    required this.unitPriceCents,
    required this.crateSize,
    required this.quantity,
    required this.orderTotalCents,
    required this.onChanged,
    required this.onMore,
    required this.onBook,
    this.accent = BarTabTheme.bottle3,
    super.key,
  });

  static const fieldKey = Key('quantity-field');
  static const minusKey = Key('quantity-minus');
  static const plusKey = Key('quantity-plus');

  final String drinkName;
  final int unitPriceCents;

  /// `null` hides the crate key (e.g. the drink left the catalog).
  final int? crateSize;
  final int quantity;

  /// Total of the whole order with [quantity] applied.
  final int orderTotalCents;
  final ValueChanged<int> onChanged;
  final VoidCallback onMore;
  final VoidCallback onBook;
  final Color accent;

  @override
  State<QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<QuantitySheet> {
  bool _fresh = true;

  void _set(int value) {
    _fresh = false;
    widget.onChanged(value.clamp(0, maxLineQuantity));
  }

  void _digit(int d) {
    if (_fresh) return _set(d);
    final next = widget.quantity * 10 + d;
    if (next > maxLineQuantity) return;
    _set(next);
  }

  void _crate() {
    final size = widget.crateSize;
    if (size == null) return;
    _set(size);
    _fresh = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const text = BarTabTheme.bottle;
    return Container(
      width: 460,
      color: BarTabTheme.paper,
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.drinkName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: text,
              fontSize: 30,
              height: 1.05,
              fontVariations: [
                FontVariation('wdth', 90),
                FontVariation('wght', 800),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.quantitySheetUnitPrice(formatCents(widget.unitPriceCents)),
            style: const TextStyle(color: text, fontSize: 17),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepButton(
                  key: QuantitySheet.minusKey,
                  icon: Icons.remove,
                  onTap: () => _set(widget.quantity - 1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    key: QuantitySheet.fieldKey,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.accent, width: 4),
                    ),
                    child: Text(
                      '${widget.quantity}',
                      style: const TextStyle(
                        color: text,
                        fontSize: 52,
                        fontVariations: [FontVariation('wght', 800)],
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _StepButton(
                  key: QuantitySheet.plusKey,
                  icon: Icons.add,
                  onTap: () => _set(widget.quantity + 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Keypad(
              crateLabel: switch (widget.crateSize) {
                final size? => l10n.quantitySheetCrate(size),
                null => null,
              },
              onDigit: _digit,
              onCrate: _crate,
              onBackspace: () => _set(widget.quantity ~/ 10),
            ),
          ),
          const SizedBox(height: 14),
          DefaultTextStyle.merge(
            style: const TextStyle(
              color: text,
              fontSize: 20,
              fontVariations: [FontVariation('wght', 700)],
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.quantitySheetTotal),
                Text(formatCents(widget.orderTotalCents)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 10,
                child: OrderButton(
                  label: l10n.quantitySheetMore,
                  solid: false,
                  onTap: widget.onMore,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 16,
                child: OrderButton(
                  label: l10n.quantitySheetBook,
                  solid: true,
                  onTap: widget.onBook,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap, super.key});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Material(
        color: BarTabTheme.bottle3,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, color: BarTabTheme.paper, size: 36),
        ),
      ),
    );
  }
}
