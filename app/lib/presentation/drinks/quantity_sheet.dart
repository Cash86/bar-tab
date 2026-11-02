import 'package:flutter/material.dart';

import '../../domain/order.dart';
import '../../l10n/app_localizations.dart';
import '../format.dart';
import '../theme.dart';
import 'keypad.dart';
import 'order_bar.dart';

/// Side sheet to set one drink's quantity with −/+ and an in-app keypad.
///
/// The value is crates × crate size + a typed number. The first digit or
/// crate press after opening discards the opened quantity; each crate press
/// adds a crate, digits append to the typed number, backspace removes the
/// last typed digit and then crates, −/+ step by one. The value stays within
/// 0..999; a press that would leave that range is ignored.
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
  // The value is `_crates × crateSize + _typed`.
  late String _typed = '${widget.quantity}';
  int _crates = 0;

  /// Still showing the opened quantity: the first digit or crate press
  /// discards it.
  bool _fresh = true;

  int get _crateSize => widget.crateSize ?? 0;

  /// Applies an edit unless the result would leave 0..999.
  void _apply(int crates, String typed) {
    final value = crates * _crateSize + (int.tryParse(typed) ?? 0);
    if (crates < 0 || value < 0 || value > maxLineQuantity) return;
    _fresh = false;
    _crates = crates;
    _typed = typed;
    widget.onChanged(value);
  }

  void _digit(int d) => _fresh ? _apply(0, '$d') : _apply(_crates, '$_typed$d');

  void _crate() {
    if (widget.crateSize == null) return;
    _fresh ? _apply(1, '') : _apply(_crates + 1, _typed);
  }

  void _backspace() {
    if (_typed.isNotEmpty) {
      _apply(_crates, _typed.substring(0, _typed.length - 1));
    } else if (_crates > 0) {
      _apply(_crates - 1, '');
    }
  }

  /// ±1 on the typed part; going below 0 there takes from a crate.
  void _step(int delta) {
    final typed = (int.tryParse(_typed) ?? 0) + delta;
    if (typed < 0) {
      if (_crates > 0) _apply(_crates - 1, '${typed + _crateSize}');
    } else {
      _apply(_crates, '$typed');
    }
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
                  onTap: () => _step(-1),
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
                  onTap: () => _step(1),
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
              onBackspace: _backspace,
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
