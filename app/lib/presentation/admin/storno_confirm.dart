import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'admin_idle.dart';

/// Asks whether to cancel the entry described by [summary]; true when
/// confirmed. Shared by the bookings and deliveries lists.
Future<bool> confirmStorno(
  BuildContext context, {
  required String title,
  required String summary,
}) async {
  final l10n = AppLocalizations.of(context);
  // A second tap during the closing animation must not pop the screen.
  var answered = false;
  void answer(BuildContext dialogContext, bool value) {
    if (answered) return;
    answered = true;
    Navigator.of(dialogContext).pop(value);
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AdminIdleGuard(
      child: AlertDialog(
        title: Text(title),
        content: Text(summary),
        actions: [
          TextButton(
            key: const Key('storno-dialog-cancel'),
            onPressed: () => answer(dialogContext, false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            key: const Key('storno-dialog-confirm'),
            onPressed: () => answer(dialogContext, true),
            child: Text(l10n.adminStorno),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
