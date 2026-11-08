import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'pairing_form.dart';

/// First-start pairing: checks the entered server and key, then stores them.
/// Leaving the screen is done by the app routing once the config is saved.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Setup is the only way forward; back must never exit the kiosk app.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.setupTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  PairingForm(onPaired: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
