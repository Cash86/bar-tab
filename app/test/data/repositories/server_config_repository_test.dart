import 'dart:async';

import 'package:bar_tab/data/repositories/server_config_repository_impl.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConfigStore implements ConfigStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  late FakeConfigStore store;
  late ServerConfigRepositoryImpl repo;

  setUp(() {
    store = FakeConfigStore();
    repo = ServerConfigRepositoryImpl(store);
  });

  test('load returns null when nothing is stored', () async {
    expect(await repo.load(), isNull);
  });

  test('load returns null when only one key is stored', () async {
    store.values['server_base_url'] = 'http://x';
    expect(await repo.load(), isNull);
  });

  test('save then load round-trips', () async {
    await repo.save(
      const ServerConfig(baseUrl: 'http://192.0.2.10:8000', deviceKey: 'k1'),
    );
    expect(store.values['server_base_url'], 'http://192.0.2.10:8000');
    expect(store.values['device_key'], 'k1');
    expect(
      await repo.load(),
      const ServerConfig(baseUrl: 'http://192.0.2.10:8000', deviceKey: 'k1'),
    );
  });

  test('base url is stored without trailing slashes', () async {
    await repo.save(
      const ServerConfig(baseUrl: 'http://192.0.2.10:8000//', deviceKey: 'k1'),
    );
    expect(store.values['server_base_url'], 'http://192.0.2.10:8000');
  });

  group('a store that never answers', () {
    late ServerConfigRepositoryImpl stuck;

    setUp(() {
      stuck = ServerConfigRepositoryImpl(
        _HangingStore(),
        timeout: const Duration(milliseconds: 20),
      );
    });

    test('load gives up and reports no config', () async {
      expect(await stuck.load(), isNull);
    });

    test('save fails with a timeout', () async {
      await expectLater(
        stuck.save(const ServerConfig(baseUrl: 'http://x', deviceKey: 'k')),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

class _HangingStore implements ConfigStore {
  @override
  Future<String?> read(String key) => Completer<String?>().future;

  @override
  Future<void> write(String key, String value) => Completer<void>().future;

  @override
  Future<void> delete(String key) => Completer<void>().future;
}
