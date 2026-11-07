import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../domain/app_design.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../drinks/keypad.dart';
import 'admin_bookings_screen.dart';
import 'admin_idle.dart';
import 'admin_session.dart';

final _log = Logger('admin');

const _minPinLength = 4;
const _maxPinLength = 8;

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
          ),
          body: loggedIn ? const _AdminHome() : const _PinPrompt(),
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
    if (_busy || _pin.length >= _maxPinLength) return;
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
            SizedBox(
              height: 40,
              child: Text(
                '•' * _pin.length,
                key: const Key('admin-pin-digits'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 32,
                  letterSpacing: 8,
                ),
              ),
            ),
            SizedBox(
              height: 24,
              child: error == null
                  ? null
                  : Text(
                      error,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: Keypad(
                crateLabel: null,
                onDigit: _digit,
                onCrate: () {},
                onBackspace: _backspace,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('admin-pin-login'),
              onPressed: _busy || _pin.length < _minPinLength ? null : _login,
              child: Text(l10n.adminPinLogin),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminHome extends ConsumerWidget {
  const _AdminHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DesignChoice(),
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('admin-bookings'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminBookingsScreen(),
                ),
              ),
              child: Text(l10n.adminBookings),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('admin-logout'),
              onPressed: () {
                unawaited(ref.read(adminSessionProvider.notifier).logout());
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: Text(l10n.adminLogout),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choice of the tablet's design; applies at once.
class _DesignChoice extends ConsumerWidget {
  const _DesignChoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final labels = {
      AppDesign.standard: l10n.designStandard,
      AppDesign.kreidetafel: l10n.designKreidetafel,
      AppDesign.bierdeckel: l10n.designBierdeckel,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.designTitle,
          style: TextStyle(color: tokens.muted, fontSize: 16),
        ),
        const SizedBox(height: 8),
        SegmentedButton<AppDesign>(
          showSelectedIcon: false,
          segments: [
            for (final MapEntry(key: design, value: label) in labels.entries)
              ButtonSegment(
                value: design,
                label: Text(label, key: Key('design-${design.storageKey}')),
              ),
          ],
          selected: {ref.watch(appDesignProvider)},
          onSelectionChanged: (choice) =>
              unawaited(_select(ref, choice.single)),
        ),
      ],
    );
  }

  /// A failed write keeps the old design; the choice can be tapped again.
  Future<void> _select(WidgetRef ref, AppDesign design) async {
    try {
      await ref.read(appDesignProvider.notifier).select(design);
    } on Object catch (e, st) {
      _log.severe('Storing the design failed', e, st);
    }
  }
}
