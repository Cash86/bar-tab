import 'package:flutter/material.dart';

import '../../domain/app_design.dart';
import '../design/chalk/chalk_extras.dart';
import '../design/coaster/coaster.dart';
import '../design/coaster/coaster_extras.dart';
import '../design/design.dart';
import '../theme.dart';

const Color _keyColor = Color(0xFFE2D8C4);

/// In-app number pad: 1–9, a crate key, 0 and backspace. Avoids the system
/// keyboard covering the drink tiles. Without [crateLabel] the crate key is
/// left out. Kreidetafel draws the keys as chalk circles, Bierdeckel as
/// small round keys with the crate key in the accent colour.
class Keypad extends StatelessWidget {
  const Keypad({
    required this.crateLabel,
    required this.onDigit,
    required this.onCrate,
    required this.onBackspace,
    this.design = AppDesign.standard,
    this.gap = 8,
    super.key,
  });

  final AppDesign design;

  /// Space between the keys.
  final double gap;

  final String? crateLabel;
  final ValueChanged<int> onDigit;
  final VoidCallback onCrate;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final ink = switch (design) {
      AppDesign.standard => BarTabTheme.bottle,
      AppDesign.kreidetafel => tokens.text,
      AppDesign.bierdeckel => kCoasterInk,
    };
    final digitStyle = switch (design) {
      AppDesign.standard => _style(28),
      AppDesign.kreidetafel => chalkStyle(tokens, 34, height: 1),
      AppDesign.bierdeckel => coasterBodyStyle(tokens, 24),
    };
    final crateStyle = switch (design) {
      AppDesign.standard => _style(18),
      AppDesign.kreidetafel => chalkStyle(
        tokens,
        20,
        color: tokens.accent,
        height: 1,
      ),
      AppDesign.bierdeckel => coasterBodyStyle(
        tokens,
        14,
        color: tokens.onAccent,
      ),
    };
    Widget key(
      Key key, {
      required VoidCallback onTap,
      required Widget child,
      bool crate = false,
    }) => switch (design) {
      AppDesign.standard => _Key(key: key, onTap: onTap, child: child),
      AppDesign.kreidetafel => _ChalkKey(
        key: key,
        color: crate ? tokens.accent : tokens.text,
        onTap: onTap,
        child: child,
      ),
      AppDesign.bierdeckel => _CoasterKey(
        key: key,
        color: crate ? tokens.accent : kCoasterPaper,
        onTap: onTap,
        child: child,
      ),
    };
    Widget digit(int d) => key(
      Key('keypad-$d'),
      onTap: () => onDigit(d),
      child: Text('$d', style: digitStyle),
    );
    final rows = [
      [digit(1), digit(2), digit(3)],
      [digit(4), digit(5), digit(6)],
      [digit(7), digit(8), digit(9)],
      [
        if (crateLabel case final label?)
          key(
            const Key('keypad-crate'),
            onTap: onCrate,
            crate: true,
            child: design == AppDesign.standard
                ? Text(label, style: crateStyle)
                // Inside a round key: "Kasten" over "(20)".
                : Text(
                    label,
                    style: crateStyle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          )
        else
          const SizedBox.shrink(),
        digit(0),
        key(
          const Key('keypad-backspace'),
          onTap: onBackspace,
          child: Icon(
            Icons.backspace_outlined,
            color: ink,
            size: design == AppDesign.bierdeckel ? 22 : 28,
          ),
        ),
      ],
    ];
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: gap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < rows[r].length; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(child: rows[r][c]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  static TextStyle _style(double size) => TextStyle(
    color: BarTabTheme.bottle,
    fontSize: size,
    fontVariations: const [FontVariation('wght', 700)],
  );
}

class _Key extends StatelessWidget {
  const _Key({required this.onTap, required this.child, super.key});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _keyColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}

/// A key drawn as a hand-drawn chalk circle.
class _ChalkKey extends StatelessWidget {
  const _ChalkKey({
    required this.color,
    required this.onTap,
    required this.child,
    super.key,
  });

  final Color color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ChalkCirclePainter(color: color),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: Padding(padding: const EdgeInsets.all(8), child: child),
          ),
        ),
      ),
    );
  }
}

/// A small round key printed on the coaster.
class _CoasterKey extends StatelessWidget {
  const _CoasterKey({
    required this.color,
    required this.onTap,
    required this.child,
    super.key,
  });

  final Color color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(
        side: BorderSide(color: Color(0xFFD8C7A6), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Padding(padding: const EdgeInsets.all(4), child: child),
        ),
      ),
    );
  }
}
