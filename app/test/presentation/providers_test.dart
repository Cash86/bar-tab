import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fakes.dart';

void main() {
  late AppDatabase db;
  late FakeApiServer server;
  late FakeSecureStore store;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    server = FakeApiServer();
    store = FakeSecureStore();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secureStoreProvider.overrideWithValue(store),
        httpClientProvider.overrideWithValue(server.client),
        clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 11, 2))),
        // Long enough that the periodic timer never fires during a test.
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('no sync service or api while unconfigured', () async {
    await container.read(serverConfigProvider.future);
    expect(container.read(apiProvider), isNull);
    expect(container.read(syncServiceProvider), isNull);
  });

  test('re-pairing rebuilds api and sync service with the new key', () async {
    await container.read(serverConfigProvider.future);
    container.listen(syncServiceProvider, (_, _) {});

    await container
        .read(serverConfigProvider.notifier)
        .save(const ServerConfig(baseUrl: 'https://a.example', deviceKey: 'A'));
    final serviceA = container.read(syncServiceProvider)!;
    await settle();
    expect(server.authHeaders, isNotEmpty);
    expect(server.authHeaders.toSet(), {'Bearer A'});

    await container
        .read(serverConfigProvider.notifier)
        .save(const ServerConfig(baseUrl: 'https://b.example', deviceKey: 'B'));
    final serviceB = container.read(syncServiceProvider)!;
    expect(serviceB, isNot(same(serviceA)));
    await settle();
    final afterRepair = server.requests.length;
    expect(server.authHeaders.last, 'Bearer B');
    expect(server.requests.last.url.host, 'b.example');

    // The old service is disposed: it no longer talks to the server.
    await serviceA.syncNow();
    expect(server.requests.length, afterRepair);
    await serviceB.syncNow();
    expect(server.requests.length, greaterThan(afterRepair));
    expect(server.authHeaders.last, 'Bearer B');
  });
}
