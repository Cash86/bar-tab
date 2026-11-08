import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
import '../../data/sync/sync_service.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import 'admin_session.dart';

final _log = Logger('admin');

/// Outcome of [saveMasterData].
sealed class SaveResult {
  const SaveResult();
}

/// Written, and the catalog now contains the change.
final class Saved extends SaveResult {
  const Saved();
}

/// Not written; [message] is shown in the dialog.
final class SaveFailed extends SaveResult {
  const SaveFailed(this.message, {this.detail});
  final String message;

  /// The server's rejection detail (e.g. `prices_incomplete`), if any.
  final String? detail;
}

/// The admin session ended; the gate shows the PIN prompt, the caller leaves
/// everything as it is.
final class SaveSessionEnded extends SaveResult {
  const SaveSessionEnded();
}

/// Runs [request] through the admin session; on success syncs and waits until
/// `catalogProvider` holds the fresh catalog.
Future<SaveResult> saveMasterData(
  WidgetRef ref,
  AppLocalizations l10n,
  Future<void> Function(BarTabApi api, String token) request,
) async {
  try {
    await ref.read(adminSessionProvider.notifier).run(request);
  } on AdminSessionEndedException {
    return const SaveSessionEnded();
  } on RejectedException catch (e) {
    _log.info('Master data rejected: ${e.detail}');
    return SaveFailed(
      e.detail == 'name_taken' ? l10n.saveNameTaken : l10n.saveFailed,
      detail: e.detail,
    );
  } on NetworkException catch (e) {
    _log.info('Master data save unreachable: ${e.message}');
    return SaveFailed(l10n.adminUnreachable);
  } on ApiException catch (e) {
    _log.warning('Master data save failed: ${e.message}');
    return SaveFailed(l10n.saveFailed);
  }
  await refreshCatalog(ref);
  return const Saved();
}

/// Runs a sync that surely starts after a write: a sync already running may
/// have fetched before the write, so it is awaited first, then one more runs.
/// Failures are logged, never thrown.
Future<void> syncAfterWrite(SyncService? sync) async {
  if (sync == null) return;
  if (sync.isSyncing) {
    try {
      await sync.syncNow();
    } on Object catch (e, st) {
      _log.warning('Running sync before the one after a write failed', e, st);
    }
  }
  try {
    await sync.syncNow();
  } on Object catch (e, st) {
    _log.warning('Sync after a write failed', e, st);
  }
}

/// Syncs and waits until `catalogProvider` holds the fresh catalog.
Future<void> refreshCatalog(WidgetRef ref) async {
  await syncAfterWrite(ref.read(syncServiceProvider));
  try {
    // The sync's own invalidation may not have landed yet: reload explicitly.
    ref.invalidate(catalogProvider);
    await ref.read(catalogProvider.future);
  } on Object catch (e, st) {
    _log.warning('Catalog reload after save failed', e, st);
  }
}
