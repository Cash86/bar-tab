import 'package:flutter/material.dart';

import '../theme.dart';

const Color _keyColor = Color(0xFFE2D8C4);

/// In-app number pad: 1–9, a crate key, 0 and backspace. Avoids the system
/// keyboard covering the drink tiles.
class Keypad extends StatelessWidget {
  const Keypad({
    required this.crateLabel,
    required this.onDigit,
    required this.onCrate,
    required this.onBackspace,
    super.key,
  });

  final String crateLabel;
  final ValueChanged<int> onDigit;
  final VoidCallback onCrate;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget digit(int d) => _Key(
      key: Key('keypad-$d'),
      onTap: () => onDigit(d),
      child: Text('$d', style: _style(28)),
    );
    final rows = [
      [digit(1), digit(2), digit(3)],
      [digit(4), digit(5), digit(6)],
      [digit(7), digit(8), digit(9)],
      [
        _Key(
          key: const Key('keypad-crate'),
          onTap: onCrate,
          child: Text(crateLabel, style: _style(18)),
        ),
        digit(0),
        _Key(
          key: const Key('keypad-backspace'),
          onTap: onBackspace,
          child: const Icon(
            Icons.backspace_outlined,
            color: BarTabTheme.bottle,
            size: 28,
          ),
        ),
      ],
    ];
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < rows[r].length; c++) ...[
                  if (c > 0) const SizedBox(width: 8),
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
