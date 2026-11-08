import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
import '../../data/repositories/local_pin_store.dart';
import '../providers.dart';

final _log = Logger('admin');

/// Minimum time between two keep-alive pings. The server drops an idle admin
/// session after 300 s, so a ping a minute keeps a reading admin logged in.
const kAdminKeepAliveInterval = Duration(seconds: 60);

enum AdminLoginResult { success, wrongPin, locked, unreachable }

/// Holds the admin token (`null` = no admin session) and keeps it alive.
final adminSessionProvider = NotifierProvider<AdminSessionNotifier, String?>(
  AdminSessionNotifier.new,
);

class AdminSessionNotifier extends Notifier<String?> {
  DateTime? _lastRequest;

  /// Bumped by [logout]: a login still in flight then must not log in.
  int _generation = 0;

  @override
  String? build() => null;

  /// Returns the outcome and, when locked, the seconds until the next try.
  Future<(AdminLoginResult, int?)> login(String pin) async {
    final api = ref.read(apiProvider);
    if (api == null) return (AdminLoginResult.unreachable, null);
    final generation = _generation;
    try {
      final result = await api.openAdminSession(pin);
      switch (result) {
        case AdminLoggedIn(:final token):
          if (generation != _generation) {
            // Logged out meanwhile: the late session is not used.
            unawaited(_revoke(api, token));
            return (AdminLoginResult.unreachable, null);
          }
          _lastRequest = ref.read(clockProvider).now();
          // A fresh login (PIN asked again) replaces the running session.
          final previous = state;
          state = token;
          if (previous != null && previous != token) {
            unawaited(_revoke(api, previous));
          }
          unawaited(_rememberPin(pin));
          return (AdminLoginResult.success, null);
        case AdminWrongPin():
          return (AdminLoginResult.wrongPin, null);
        case AdminLockedOut(:final retryAfter):
          return (AdminLoginResult.locked, retryAfter);
      }
    } on NetworkException catch (e) {
      _log.info('Admin login unreachable: ${e.message}');
      return (AdminLoginResult.unreachable, null);
    } on ApiException catch (e) {
      _log.warning('Admin login failed: ${e.message}');
      return (AdminLoginResult.unreachable, null);
    }
  }

  /// Keeps a hash of the accepted PIN for offline re-pairing; best effort.
  Future<void> _rememberPin(String pin) async {
    try {
      await ref.read(localPinStoreProvider).remember(pin);
    } on Object catch (e) {
      _log.warning('Local admin PIN not stored: $e');
    }
  }

  /// Drops the token at once; the server is told on a best-effort basis,
  /// through [via] when given (the old server after a re-pairing).
  Future<void> logout({BarTabApi? via}) async {
    final token = state;
    _generation++;
    state = null;
    _lastRequest = null;
    final api = via ?? ref.read(apiProvider);
    if (token == null || api == null) return;
    await _revoke(api, token);
  }

  Future<void> _revoke(BarTabApi api, String token) async {
    try {
      await api.closeAdminSession(token);
    } on ApiException catch (e) {
      _log.info('Admin logout not confirmed: ${e.message}');
    }
  }

  /// Called on every user interaction in the admin area.
  void onInteraction() {
    final token = state;
    final api = ref.read(apiProvider);
    final last = _lastRequest;
    if (token == null || api == null || last == null) return;
    final now = ref.read(clockProvider).now();
    if (now.difference(last) < kAdminKeepAliveInterval) return;
    _lastRequest = now;
    unawaited(_ping(api, token));
  }

  Future<void> _ping(BarTabApi api, String token) async {
    try {
      await api.pingAdmin(token);
    } on AdminSessionEndedException {
      _endSession(token);
    } on ApiException catch (e) {
      _log.info('Admin keep-alive failed: ${e.message}');
    }
  }

  /// Runs an admin request with the current token and counts it as activity.
  Future<T> run<T>(
    Future<T> Function(BarTabApi api, String token) request,
  ) async {
    final token = state;
    final api = ref.read(apiProvider);
    if (token == null || api == null) throw const AdminSessionEndedException();
    _lastRequest = ref.read(clockProvider).now();
    try {
      return await request(api, token);
    } on AdminSessionEndedException {
      _endSession(token);
      rethrow;
    }
  }

  void _endSession(String token) {
    if (state != token) return;
    state = null;
    _lastRequest = null;
  }
}

/// Local PIN lockout, as on the server: the fifth failure locks for 60 s.
const kLocalPinMaxFailures = 5;
const kLocalPinLockout = Duration(seconds: 60);

/// `true` while the repair-only admin area is unlocked with the local PIN
/// hash (the server could not verify the PIN).
final localAdminProvider = NotifierProvider<LocalAdminNotifier, bool>(
  LocalAdminNotifier.new,
);

class LocalAdminNotifier extends Notifier<bool> {
  int _failures = 0;
  DateTime? _lockedUntil;

  /// Bumped by [lock]: an unlock still in flight then must not unlock.
  int _generation = 0;

  @override
  bool build() => false;

  /// Checks [pin] against the local hash. `unreachable` when no hash is
  /// stored (the offline path is not available); when locked, the seconds
  /// until the next try.
  Future<(AdminLoginResult, int?)> unlock(String pin) async {
    final store = ref.read(localPinStoreProvider);
    final generation = _generation;
    if (!await _hasPin(store)) return (AdminLoginResult.unreachable, null);
    final now = ref.read(clockProvider).now();
    final until = _lockedUntil;
    if (until != null) {
      final remaining = until.difference(now);
      if (remaining > Duration.zero) {
        return (
          AdminLoginResult.locked,
          (remaining.inMilliseconds / 1000).ceil(),
        );
      }
      _lockedUntil = null;
      _failures = 0;
    }
    // Counted before the slow check, like the server does.
    _failures++;
    if (_failures >= kLocalPinMaxFailures) {
      _lockedUntil = now.add(kLocalPinLockout);
    }
    if (!await store.verify(pin)) return (AdminLoginResult.wrongPin, null);
    _failures = 0;
    _lockedUntil = null;
    if (generation != _generation) return (AdminLoginResult.unreachable, null);
    state = true;
    return (AdminLoginResult.success, null);
  }

  Future<bool> _hasPin(LocalPinStore store) async {
    try {
      return await store.hasPin();
    } on Object catch (e) {
      _log.warning('Local admin PIN not readable: $e');
      return false;
    }
  }

  /// Ends the local unlock; the failure count and lockout stay.
  void lock() {
    _generation++;
    state = false;
  }
}
