import 'dart:async';

import 'package:logging/logging.dart';

import '../../domain/repositories.dart';
import '../../domain/sync_state.dart';

/// Minimal key-value store for the tablet's pairing, kept in app-private
/// storage (the Android sandbox is the protection).
abstract interface class ConfigStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);

  /// Writes all [entries] or none of them.
  Future<void> writeAll(Map<String, String> entries);
  Future<void> delete(String key);
}

final _log = Logger('server_config');

class ServerConfigRepositoryImpl implements ServerConfigRepository {
  /// Every store call is bounded by [timeout]: a hung store must not leave the
  /// app on the splash screen or the setup button spinning.
  ServerConfigRepositoryImpl(
    this._store, {
    this.timeout = const Duration(seconds: 5),
  });

  static const baseUrlKey = 'server_base_url';
  static const deviceKeyKey = 'device_key';

  final ConfigStore _store;
  final Duration timeout;

  @override
  Future<ServerConfig?> load() async {
    try {
      final baseUrl = await _store.read(baseUrlKey).timeout(timeout);
      final deviceKey = await _store.read(deviceKeyKey).timeout(timeout);
      if (baseUrl == null || deviceKey == null) return null;
      return ServerConfig(baseUrl: baseUrl, deviceKey: deviceKey);
    } on Object catch (e, st) {
      _log.severe('Reading the server config failed', e, st);
      return null;
    }
  }

  @override
  Future<void> save(ServerConfig config) async {
    await _store
        .writeAll({
          baseUrlKey: config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
          deviceKeyKey: config.deviceKey,
        })
        .timeout(timeout);
  }
}
