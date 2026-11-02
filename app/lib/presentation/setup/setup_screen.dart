import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sync_state.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';

enum _SetupError { invalidUrl, unauthorised, unreachable }

/// First-start pairing: checks the entered server and key, then stores them.
/// Leaving the screen is done by the app routing once the config is saved.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _checking = false;
  _SetupError? _error;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  static String? _normalisedUrl(String input) {
    final trimmed = input.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return trimmed;
  }

  Future<void> _connect() async {
    final baseUrl = _normalisedUrl(_url.text);
    if (baseUrl == null) {
      setState(() => _error = _SetupError.invalidUrl);
      return;
    }
    final config = ServerConfig(baseUrl: baseUrl, deviceKey: _key.text.trim());
    setState(() {
      _checking = true;
      _error = null;
    });
    _SetupError? error = _SetupError.unreachable;
    try {
      error = switch (await ref.read(pairingProvider).pair(config)) {
        PairingResult.success => null,
        PairingResult.unauthorised => _SetupError.unauthorised,
        PairingResult.unreachable => _SetupError.unreachable,
      };
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final errorText = switch (_error) {
      _SetupError.invalidUrl => l10n.setupErrorInvalidUrl,
      _SetupError.unauthorised => l10n.setupErrorUnauthorised,
      _SetupError.unreachable => l10n.setupErrorUnreachable,
      null => null,
    };
    return Scaffold(
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
                TextField(
                  key: const Key('setup-url'),
                  controller: _url,
                  enabled: !_checking,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.setupServerUrlLabel,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('setup-key'),
                  controller: _key,
                  enabled: !_checking,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l10n.setupDeviceKeyLabel,
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    errorText,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _checking ? null : _connect,
                  child: _checking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.setupConnectButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
