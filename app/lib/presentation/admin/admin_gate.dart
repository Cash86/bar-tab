import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import 'admin_home.dart';
import 'admin_idle.dart';
import 'admin_route.dart';
import 'admin_session.dart';
import 'pin_pad.dart';
import 'repair_screen.dart';

/// Entry to the admin area: the PIN prompt without an admin session,
/// otherwise the admin home. When the server cannot verify the PIN, the
/// local PIN hash opens a repair-only home. Shows the prompt again when the
/// session ends.
class AdminGate extends ConsumerWidget {
  const AdminGate({super.key});

  /// Server login; when the server is unreachable or rejects the device key,
  /// the local hash (if any) decides.
  static Future<(AdminLoginResult, int?)> _login(
    BuildContext context,
    WidgetRef ref,
    String pin,
  ) async {
    final local = ref.read(localAdminProvider.notifier);
    final online = await ref.read(adminSessionProvider.notifier).login(pin);
    if (online.$1 != AdminLoginResult.unreachable) return online;
    // Gate left meanwhile: nothing may be unlocked any more.
    if (!context.mounted) return online;
    return local.unlock(pin);
  }

  void _leave(BuildContext context, WidgetRef ref) {
    unawaited(ref.read(adminSessionProvider.notifier).logout());
    ref.read(localAdminProvider.notifier).lock();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Online: the PIN is checked by the server again before the warning.
  Future<void> _repairOnline(BuildContext context) async {
    final confirmed = await Navigator.of(
      context,
    ).push<bool>(adminRoute((_) => const _RepairPinScreen()));
    if (confirmed == true && context.mounted) await confirmRepair(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final loggedIn = ref.watch(adminSessionProvider) != null;
    final local = !loggedIn && ref.watch(localAdminProvider);
    final inside = loggedIn || local;
    return AdminIdleGuard(
      // Inside, the area is left only by logging out or by idling, so the
      // session (or local unlock) always ends with it.
      child: PopScope(
        canPop: !inside,
        // Leaving the prompt cancels a login still in flight, so a late
        // token is revoked instead of living on without this guard.
        onPopInvokedWithResult: (didPop, _) {
          if (didPop && !inside) {
            unawaited(ref.read(adminSessionProvider.notifier).logout());
            ref.read(localAdminProvider.notifier).lock();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(local ? l10n.adminOfflineTitle : l10n.adminTitle),
            automaticallyImplyLeading: !inside,
            actions: [
              if (inside)
                TextButton(
                  key: const Key('admin-logout'),
                  onPressed: () => _leave(context, ref),
                  child: Text(l10n.adminLogout),
                ),
            ],
          ),
          body: loggedIn
              ? AdminHome(onRepair: () => unawaited(_repairOnline(context)))
              : local
              ? const _RepairOnlyHome()
              : _PinPrompt(submit: (pin) => _login(context, ref, pin)),
        ),
      ),
    );
  }
}

/// Offline admin area: re-pairing is all it offers. The PIN was just checked
/// locally, so the warning follows directly.
class _RepairOnlyHome extends StatelessWidget {
  const _RepairOnlyHome();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        key: const Key('admin-repair'),
        onPressed: () => unawaited(confirmRepair(context)),
        child: Text(AppLocalizations.of(context).adminRepair),
      ),
    );
  }
}

/// The PIN asked again by the server before an online re-pairing; pops
/// `true` once a fresh admin session replaced the old one.
class _RepairPinScreen extends ConsumerWidget {
  const _RepairPinScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).adminRepair)),
        body: _PinPrompt(
          submit: (pin) => ref.read(adminSessionProvider.notifier).login(pin),
          onSuccess: () => Navigator.of(context).pop(true),
        ),
      ),
    );
  }
}

class _PinPrompt extends ConsumerStatefulWidget {
  const _PinPrompt({required this.submit, this.onSuccess});

  final Future<(AdminLoginResult, int?)> Function(String pin) submit;
  final VoidCallback? onSuccess;

  @override
  ConsumerState<_PinPrompt> createState() => _PinPromptState();
}

class _PinPromptState extends ConsumerState<_PinPrompt> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  void _digit(int d) {
    if (_busy || _pin.length >= kMaxPinLength) return;
    setState(() => _pin += '$d');
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    final (result, retryAfter) = await widget.submit(_pin);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _pin = '';
      _error = switch (result) {
        AdminLoginResult.success => null,
        AdminLoginResult.wrongPin => l10n.adminPinWrong,
        AdminLoginResult.locked => l10n.adminPinLocked(retryAfter ?? 0),
        AdminLoginResult.unreachable => l10n.adminUnreachable,
      };
    });
    if (result == AdminLoginResult.success) widget.onSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final error = _error;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.adminPinTitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.text, fontSize: 24),
            ),
            const SizedBox(height: 12),
            PinPad(
              pin: _pin,
              error: error,
              onDigit: _digit,
              onBackspace: _backspace,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('admin-pin-login'),
              onPressed: _busy || _pin.length < kMinPinLength ? null : _login,
              child: Text(l10n.adminPinLogin),
            ),
          ],
        ),
      ),
    );
  }
}
