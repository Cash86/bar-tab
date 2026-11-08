import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import 'admin_home.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'pin_pad.dart';

/// Entry to the admin area: the PIN prompt without an admin session,
/// otherwise the admin home. Shows the prompt again when the session ends.
class AdminGate extends ConsumerWidget {
  const AdminGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(adminSessionProvider) != null;
    return AdminIdleGuard(
      // Logged in, the area is left only by logging out or by idling, so
      // the session always ends with it.
      child: PopScope(
        canPop: !loggedIn,
        // Leaving the prompt cancels a login still in flight, so a late
        // token is revoked instead of living on without this guard.
        onPopInvokedWithResult: (didPop, _) {
          if (didPop && !loggedIn) {
            unawaited(ref.read(adminSessionProvider.notifier).logout());
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.of(context).adminTitle),
            automaticallyImplyLeading: !loggedIn,
            actions: [
              if (loggedIn)
                TextButton(
                  key: const Key('admin-logout'),
                  onPressed: () {
                    unawaited(ref.read(adminSessionProvider.notifier).logout());
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  child: Text(AppLocalizations.of(context).adminLogout),
                ),
            ],
          ),
          body: loggedIn ? const AdminHome() : const _PinPrompt(),
        ),
      ),
    );
  }
}

class _PinPrompt extends ConsumerStatefulWidget {
  const _PinPrompt();

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
    final (result, retryAfter) = await ref
        .read(adminSessionProvider.notifier)
        .login(_pin);
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
