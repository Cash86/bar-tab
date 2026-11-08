import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../domain/sync_state.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../setup/pairing_form.dart';
import 'admin_home.dart';
import 'admin_idle.dart';
import 'admin_session.dart';

/// Shows the re-pairing warning and, when confirmed, the pairing form.
Future<void> confirmRepair(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AdminIdleGuard(
      child: AlertDialog(
        content: Text(l10n.repairWarning),
        actions: [
          TextButton(
            key: const Key('repair-cancel'),
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            key: const Key('repair-continue'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.repairContinue),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  openAdminScreen(context, const RepairScreen());
}

/// The first-start form, pre-filled with the current pairing. Only a pairing
/// the new server accepts replaces the stored one; then the admin area ends
/// and the app returns to the name list.
class RepairScreen extends ConsumerStatefulWidget {
  const RepairScreen({super.key});

  @override
  ConsumerState<RepairScreen> createState() => _RepairScreenState();
}

class _RepairScreenState extends ConsumerState<RepairScreen> {
  /// Talks to the old server, where the admin session (if any) lives; read
  /// before the pairing changes.
  BarTabApi? _oldApi;
  ServerConfig? _current;

  @override
  void initState() {
    super.initState();
    _oldApi = ref.read(apiProvider);
    _current = ref.read(serverConfigProvider).value;
  }

  void _paired() {
    unawaited(ref.read(adminSessionProvider.notifier).logout(via: _oldApi));
    ref.read(localAdminProvider.notifier).lock();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.adminRepair)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: PairingForm(
                initial: _current,
                repair: true,
                onPaired: _paired,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
