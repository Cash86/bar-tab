import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../providers.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'pin_pad.dart';

final _log = Logger('admin');

enum _Step { current, next, repeat }

/// Change the admin PIN: current PIN, new PIN, new PIN again.
class PinChangeScreen extends ConsumerStatefulWidget {
  const PinChangeScreen({super.key});

  @override
  ConsumerState<PinChangeScreen> createState() => _PinChangeScreenState();
}

class _PinChangeScreenState extends ConsumerState<PinChangeScreen> {
  _Step _step = _Step.current;
  String _current = '';
  String _next = '';
  String _repeat = '';
  bool _busy = false;
  String? _error;

  String get _entry => switch (_step) {
    _Step.current => _current,
    _Step.next => _next,
    _Step.repeat => _repeat,
  };

  set _entry(String value) {
    switch (_step) {
      case _Step.current:
        _current = value;
      case _Step.next:
        _next = value;
      case _Step.repeat:
        _repeat = value;
    }
  }

  void _digit(int d) {
    if (_busy || _entry.length >= kMaxPinLength) return;
    setState(() => _entry = '$_entry$d');
  }

  void _backspace() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  /// The session ended: back to the gate, which shows the PIN prompt.
  void _leave() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  Future<void> _confirm() async {
    if (_busy || _entry.length < kMinPinLength) return;
    final l10n = AppLocalizations.of(context);
    switch (_step) {
      case _Step.current:
        setState(() {
          _step = _Step.next;
          _error = null;
        });
      case _Step.next:
        setState(() {
          _step = _Step.repeat;
          _error = null;
        });
      case _Step.repeat:
        if (_repeat != _next) {
          setState(() {
            _step = _Step.next;
            _next = _repeat = '';
            _error = l10n.pinChangeMismatch;
          });
          return;
        }
        await _submit(l10n);
    }
  }

  Future<void> _submit(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final current = _current;
    final next = _next;
    setState(() {
      _busy = true;
      _error = null;
    });
    PinChange result;
    try {
      result = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.changeAdminPin(token, current, next));
    } on AdminSessionEndedException {
      if (mounted) setState(() => _busy = false);
      return;
    } on NetworkException catch (e) {
      _log.info('PIN change unreachable: ${e.message}');
      _fail(l10n.adminUnreachable);
      return;
    } on ApiException catch (e) {
      _log.info('PIN change failed: ${e.message}');
      _fail(l10n.pinChangeFailed);
      return;
    }
    switch (result) {
      case PinChanged():
        try {
          await ref.read(localPinStoreProvider).remember(next);
        } on Object catch (e) {
          _log.warning('Local admin PIN not stored: $e');
        }
        messenger.showSnackBar(SnackBar(content: Text(l10n.pinChangeDone)));
        if (mounted) navigator.pop();
      case PinWrong():
        _fail(l10n.adminPinWrong, restart: true);
      case PinLocked(:final retryAfter):
        _fail(l10n.adminPinLocked(retryAfter), restart: true);
    }
  }

  void _fail(String message, {bool restart = false}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      if (restart) {
        _step = _Step.current;
        _current = _next = _repeat = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminSessionProvider, (_, token) {
      if (token == null) _leave();
    });
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final title = switch (_step) {
      _Step.current => l10n.pinChangeCurrent,
      _Step.next => l10n.pinChangeNew,
      _Step.repeat => l10n.pinChangeRepeat,
    };
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.pinChangeTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.text, fontSize: 24),
                ),
                const SizedBox(height: 12),
                PinPad(
                  pin: _entry,
                  error: _error,
                  onDigit: _digit,
                  onBackspace: _backspace,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('pin-change-next'),
                  onPressed: _busy || _entry.length < kMinPinLength
                      ? null
                      : _confirm,
                  child: Text(
                    _step == _Step.repeat
                        ? l10n.pinChangeSave
                        : l10n.pinChangeNext,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
