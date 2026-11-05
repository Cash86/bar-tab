import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
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

  @override
  String? build() => null;

  /// Returns the outcome and, when locked, the seconds until the next try.
  Future<(AdminLoginResult, int?)> login(String pin) async {
    final api = ref.read(apiProvider);
    if (api == null) return (AdminLoginResult.unreachable, null);
    try {
      final result = await api.openAdminSession(pin);
      switch (result) {
        case AdminLoggedIn(:final token):
          _lastRequest = ref.read(clockProvider).now();
          state = token;
          return (AdminLoginResult.success, null);
        case AdminWrongPin():
          return (AdminLoginResult.wrongPin, null);
        case AdminLockedOut(:final retryAfter):
          return (AdminLoginResult.locked, retryAfter);
      }
    } on NetworkException catch (e) {
      _log.info('Admin login unreachable: ${e.message}');
      return (AdminLoginResult.unreachable, null);
    }
  }

  /// Drops the token at once; the server is told on a best-effort basis.
  Future<void> logout() async {
    final token = state;
    state = null;
    _lastRequest = null;
    final api = ref.read(apiProvider);
    if (token == null || api == null) return;
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
