import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import 'admin_session.dart';

final _log = Logger('admin');

/// Runs [request] through the admin session; on success triggers syncNow() and waits for the
/// catalog to reload. Returns null on success or the error text to show in the dialog.
Future<String?> saveMasterData(
  WidgetRef ref,
  AppLocalizations l10n,
  Future<void> Function(BarTabApi api, String token) request,
) async {
  try {
    await ref.read(adminSessionProvider.notifier).run(request);
  } on AdminSessionEndedException {
    // The gate shows the PIN prompt.
    return null;
  } on RejectedException catch (e) {
    _log.info('Master data rejected: ${e.detail}');
    return e.detail == 'name_taken' ? l10n.saveNameTaken : l10n.saveFailed;
  } on NetworkException catch (e) {
    _log.info('Master data save unreachable: ${e.message}');
    return l10n.adminUnreachable;
  } on ApiException catch (e) {
    _log.warning('Master data save failed: ${e.message}');
    return l10n.saveFailed;
  }
  try {
    await ref.read(syncServiceProvider)?.syncNow();
  } on Object catch (e, st) {
    _log.warning('Sync after master data save failed', e, st);
  }
  try {
    await ref.read(catalogProvider.future);
  } on Object catch (e, st) {
    _log.warning('Catalog reload after save failed', e, st);
  }
  return null;
}
