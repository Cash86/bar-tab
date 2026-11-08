import 'package:flutter/material.dart';

import '../design/design.dart';
import '../drinks/keypad.dart';

const kMinPinLength = 4;
const kMaxPinLength = 8;

/// Masked PIN dots, a line for an error and the keypad; shared by the admin
/// PIN prompt and the PIN change.
class PinPad extends StatelessWidget {
  const PinPad({
    required this.pin,
    required this.error,
    required this.onDigit,
    required this.onBackspace,
    super.key,
  });

  final String pin;
  final String? error;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final error = this.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Text(
            '•' * pin.length,
            key: const Key('admin-pin-digits'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.text,
              fontSize: 32,
              letterSpacing: 8,
            ),
          ),
        ),
        SizedBox(
          height: 24,
          child: error == null
              ? null
              : Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 16,
                  ),
                ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: Keypad(
            crateLabel: null,
            onDigit: onDigit,
            onCrate: () {},
            onBackspace: onBackspace,
          ),
        ),
      ],
    );
  }
}
