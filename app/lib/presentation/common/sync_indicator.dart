import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sync_state.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../providers.dart';

/// Text for [state], or null when there is nothing to report.
///
/// Precedence: unauthorised, then failed, then queued. If both failed and
/// queued bookings exist only the failed text is shown. Being offline alone
/// is normal and not reported.
String? syncIndicatorText(AppLocalizations l10n, SyncState state) {
  if (state.isUnauthorised) return l10n.syncUnauthorised;
  if (state.failed > 0) return l10n.syncFailed(state.failed);
  if (state.queued > 0) return l10n.syncQueued(state.queued);
  return null;
}

/// Small, muted sync status; renders nothing when everything is synced.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateProvider).value;
    if (state == null) return const SizedBox.shrink();
    final text = syncIndicatorText(AppLocalizations.of(context), state);
    if (text == null) return const SizedBox.shrink();
    final tokens = DesignTokens.of(context);
    return Text(
      text,
      style: TextStyle(
        color: tokens.muted,
        fontSize: 14,
        fontWeight: tokens.setsFontWeight ? FontWeight.w500 : null,
        fontVariations: const [FontVariation('wght', 500)],
      ),
    );
  }
}
