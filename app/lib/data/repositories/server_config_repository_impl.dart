import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/repositories.dart';
import '../../domain/sync_state.dart';

/// Minimal key-value store for secrets.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class ServerConfigRepositoryImpl implements ServerConfigRepository {
  ServerConfigRepositoryImpl(this._store);

  static const baseUrlKey = 'server_base_url';
  static const deviceKeyKey = 'device_key';

  final SecureStore _store;

  @override
  Future<ServerConfig?> load() async {
    final baseUrl = await _store.read(baseUrlKey);
    final deviceKey = await _store.read(deviceKeyKey);
    if (baseUrl == null || deviceKey == null) return null;
    return ServerConfig(baseUrl: baseUrl, deviceKey: deviceKey);
  }

  @override
  Future<void> save(ServerConfig config) async {
    await _store.write(
      baseUrlKey,
      config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
    );
    await _store.write(deviceKeyKey, config.deviceKey);
  }
}
