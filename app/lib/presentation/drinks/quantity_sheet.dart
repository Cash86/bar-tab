import 'package:flutter/material.dart';

import '../../domain/app_design.dart';

import '../../domain/order.dart';
import '../../l10n/app_localizations.dart';
import '../design/chalk/chalk_board.dart';
import '../design/chalk/chalk_extras.dart';
import '../design/chalk_text.dart';
import '../design/coaster/coaster.dart';
import '../design/coaster/coaster_extras.dart';
import '../design/design.dart';
import '../format.dart';
import '../theme.dart';
import 'keypad.dart';
import 'order_bar.dart';

/// The dimmed selection behind the sheet.
Color quantitySheetScrim(AppDesign design) => switch (design) {
  AppDesign.standard => const Color(0x9916302A),
  AppDesign.kreidetafel => const Color(0x8C0A0C0B),
  AppDesign.bierdeckel => const Color(0x8C06100C),
};

/// Side sheet to set one drink's quantity with −/+ and an in-app keypad.
///
/// The value is crates × crate size + a typed number. The first digit or
/// crate press after opening discards the opened quantity; each crate press
/// adds a crate, digits append to the typed number, backspace removes the
/// last typed digit and then crates, −/+ step by one. The value stays within
/// 0..999; a press that would leave that range is ignored.
///
/// Standard docks it on the right; Kreidetafel shows a small framed slate
/// board, Bierdeckel a large coaster with the buttons beside it. Both are
/// meant to be centred over the selection.
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
    this.design = AppDesign.standard,
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
  final AppDesign design;

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
  Widget build(BuildContext context) => switch (widget.design) {
    AppDesign.standard => _standard(context),
    AppDesign.kreidetafel => _chalk(context),
    AppDesign.bierdeckel => _coaster(context),
  };

  Widget _keypad(BuildContext context, {double gap = 8}) {
    final l10n = AppLocalizations.of(context);
    return Keypad(
      design: widget.design,
      gap: gap,
      crateLabel: switch (widget.crateSize) {
        final size? => l10n.quantitySheetCrate(size),
        null => null,
      },
      onDigit: _digit,
      onCrate: _crate,
      onBackspace: _backspace,
    );
  }

  /// −, the quantity and + in a row of [height].
  Widget _quantityRow({
    required double height,
    required double gap,
    required Widget Function(Key key, IconData icon, VoidCallback onTap) step,
    required Widget field,
  }) => SizedBox(
    height: height,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        step(QuantitySheet.minusKey, Icons.remove, () => _step(-1)),
        SizedBox(width: gap),
        Expanded(child: field),
        SizedBox(width: gap),
        step(QuantitySheet.plusKey, Icons.add, () => _step(1)),
      ],
    ),
  );

  // Kreidetafel: name, quantity, total and buttons on the left of a framed
  // slate board, the chalk-circle keypad on the right.
  static const double _chalkKey = 80;
  static const double _chalkGap = 10;

  Widget _chalk(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final chalk = tokens.text;
    final yellow = tokens.accent;
    return Transform.rotate(
      angle: -0.006,
      child: SizedBox(
        width: 780,
        height: 500,
        child: ChalkBoard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 18, 26, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 70,
                        child: ChalkText(
                          widget.drinkName,
                          style: chalkStyle(tokens, 44, height: 1),
                          minFontSize: 24,
                          maxLines: 2,
                        ),
                      ),
                      Text(
                        l10n.quantitySheetUnitPrice(
                          formatCents(widget.unitPriceCents),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: chalkStyle(tokens, 24, color: tokens.muted),
                      ),
                      const SizedBox(height: 8),
                      _quantityRow(
                        height: _chalkKey,
                        gap: 12,
                        step: (key, icon, onTap) => SizedBox(
                          width: _chalkKey,
                          child: CustomPaint(
                            key: key,
                            painter: ChalkCirclePainter(color: chalk),
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                onTap: onTap,
                                customBorder: const CircleBorder(),
                                child: Icon(icon, color: chalk, size: 34),
                              ),
                            ),
                          ),
                        ),
                        field: CustomPaint(
                          key: QuantitySheet.fieldKey,
                          painter: _DashedUnderline(
                            chalk.withValues(alpha: 0.5),
                          ),
                          child: Center(
                            child: Text(
                              '${widget.quantity}',
                              maxLines: 1,
                              style:
                                  chalkStyle(
                                    tokens,
                                    72,
                                    color: yellow,
                                    height: 1,
                                  ).copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.quantitySheetTotal,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: chalkStyle(tokens, 28),
                            ),
                          ),
                          Text(
                            formatCents(widget.orderTotalCents),
                            style: chalkStyle(tokens, 30, color: yellow)
                                .copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 58,
                        child: OrderButton(
                          design: widget.design,
                          label: l10n.quantitySheetBook,
                          solid: true,
                          onTap: widget.onBook,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 58,
                        child: OrderButton(
                          design: widget.design,
                          label: l10n.quantitySheetMore,
                          solid: false,
                          onTap: widget.onMore,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                Center(
                  child: SizedBox(
                    width: 3 * _chalkKey + 2 * _chalkGap,
                    height: 4 * _chalkKey + 3 * _chalkGap,
                    child: _keypad(context, gap: _chalkGap),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Bierdeckel: a large coaster carries name, quantity and keypad; total
  // and buttons sit beside it so it stays round. A blank column as wide as
  // the buttons on the other side keeps the coaster in the middle.
  static const double _disc = 560;
  static const double _side = 260;
  static const double _sideGap = 28;
  static const double _coasterKey = 56;

  Widget _coaster(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    Widget round(Key key, IconData icon, VoidCallback onTap) => SizedBox(
      width: _coasterKey,
      child: Material(
        key: key,
        color: kCoasterPaper,
        shape: const CircleBorder(
          side: BorderSide(color: Color(0xFFD8C7A6), width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, color: kCoasterInk, size: 28),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: _side + _sideGap),
        SheetCoaster(
          diameter: _disc,
          ring: widget.accent,
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 64,
                  child: ChalkText(
                    widget.drinkName,
                    style: coasterDisplayStyle(tokens, 30),
                    minFontSize: 16,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.quantitySheetUnitPrice(
                    formatCents(widget.unitPriceCents),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: coasterBodyStyle(tokens, 19, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 260,
                  child: _quantityRow(
                    height: _coasterKey,
                    gap: 10,
                    step: round,
                    field: Center(
                      key: QuantitySheet.fieldKey,
                      child: Text(
                        '${widget.quantity}',
                        maxLines: 1,
                        style:
                            coasterDisplayStyle(
                              tokens,
                              48,
                              color: tokens.accent,
                            ).copyWith(
                              height: 1,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 3 * _coasterKey + 2 * 8,
                  height: 4 * _coasterKey + 3 * 8,
                  child: _keypad(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: _sideGap),
        SizedBox(
          width: _side,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.quantitySheetTotal,
                style: coasterBodyStyle(tokens, 22, color: kCoasterPaper),
              ),
              Text(
                formatCents(widget.orderTotalCents),
                style: coasterDisplayStyle(
                  tokens,
                  36,
                  color: kCoasterPaper,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 18),
              CoasterButton(
                label: l10n.quantitySheetBook,
                primary: true,
                onTap: widget.onBook,
                fontSize: 22,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              const SizedBox(height: 12),
              CoasterButton(
                label: l10n.quantitySheetMore,
                primary: false,
                onTap: widget.onMore,
                fontSize: 22,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _standard(BuildContext context) {
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

/// A dashed chalk line along the bottom of its box.
class _DashedUnderline extends CustomPainter {
  const _DashedUnderline(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final y = size.height - 2;
    for (var x = 4.0; x < size.width - 4; x += 12) {
      canvas.drawLine(Offset(x, y), Offset(x + 7, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedUnderline old) => old.color != color;
}
