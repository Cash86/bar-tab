import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sync_state.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';

enum _PairingError { invalidUrl, unauthorised, unreachable }

/// Server address and device key, checked against the server before they
/// are stored (first start and re-pairing). [onPaired] runs after success
/// while the form is still shown.
class PairingForm extends ConsumerStatefulWidget {
  const PairingForm({
    super.key,
    this.initial,
    required this.onPaired,
    this.repair = false,
  });

  /// Pre-fills the fields (re-pairing: the current pairing).
  final ServerConfig? initial;
  final VoidCallback onPaired;

  /// Passed to [Pairing.pair]: drops the old server's cached data.
  final bool repair;

  @override
  ConsumerState<PairingForm> createState() => _PairingFormState();
}

class _PairingFormState extends ConsumerState<PairingForm> {
  late final _url = TextEditingController(text: widget.initial?.baseUrl);
  late final _key = TextEditingController(text: widget.initial?.deviceKey);
  bool _checking = false;
  _PairingError? _error;

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
      setState(() => _error = _PairingError.invalidUrl);
      return;
    }
    final config = ServerConfig(baseUrl: baseUrl, deviceKey: _key.text.trim());
    setState(() {
      _checking = true;
      _error = null;
    });
    _PairingError? error = _PairingError.unreachable;
    try {
      error = switch (await ref
          .read(pairingProvider)
          .pair(config, repair: widget.repair)) {
        PairingResult.success => null,
        PairingResult.unauthorised => _PairingError.unauthorised,
        PairingResult.unreachable => _PairingError.unreachable,
      };
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = error;
        });
      }
    }
    if (error == null && mounted) widget.onPaired();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final errorText = switch (_error) {
      _PairingError.invalidUrl => l10n.setupErrorInvalidUrl,
      _PairingError.unauthorised => l10n.setupErrorUnauthorised,
      _PairingError.unreachable => l10n.setupErrorUnreachable,
      null => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('setup-url'),
          controller: _url,
          enabled: !_checking,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(labelText: l10n.setupServerUrlLabel),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('setup-key'),
          controller: _key,
          enabled: !_checking,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: l10n.setupDeviceKeyLabel),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 16),
          Text(
            errorText,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    );
  }
}
