import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../l10n/app_localizations.dart';
import 'admin_idle.dart';
import 'master_data_save.dart';

/// Asks "[title]?" and, when confirmed, runs [request] through the admin
/// session like [saveMasterData]. Null when the question was cancelled or the
/// caller went away meanwhile. A rejection (the entry became used meanwhile)
/// reloads the catalog so the caller shows the current state.
Future<SaveResult?> confirmAndDelete(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required Key confirmKey,
  required Key cancelKey,
  required Future<void> Function(BarTabApi api, String token) request,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AdminIdleGuard(
      child: AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            key: cancelKey,
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            key: confirmKey,
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.masterDelete),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return null;
  final result = await saveMasterData(ref, l10n, request);
  if (result case SaveFailed(detail: != null)) await refreshCatalog(ref);
  return result;
}
