import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/api/api_client.dart';
import '../data/db/database.dart';
import '../data/repositories/booking_repository_impl.dart';
import '../data/repositories/catalog_repository_impl.dart';
import '../data/repositories/server_config_repository_impl.dart';
import '../data/repositories/tabs_repository_impl.dart';
import '../data/sync/sync_service.dart';
import '../domain/catalog.dart';
import '../domain/clock.dart';
import '../domain/repositories.dart';
import '../domain/running_total.dart';
import '../domain/sync_state.dart';

final clockProvider = Provider<Clock>((ref) => SystemClock());

/// Must be overridden with the opened database (see `main.dart`).
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final secureStoreProvider = Provider<SecureStore>(
  (ref) => FlutterSecureStore(),
);

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Period of background syncs; `null` disables the sync loop (tests).
final syncIntervalProvider = Provider<Duration?>(
  (ref) => SyncService.defaultInterval,
);

final serverConfigRepositoryProvider = Provider<ServerConfigRepository>(
  (ref) => ServerConfigRepositoryImpl(ref.watch(secureStoreProvider)),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepositoryImpl(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  ),
);

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepositoryImpl(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  ),
);

final tabsRepositoryProvider = Provider<TabsRepository>(
  (ref) =>
      TabsRepositoryImpl(ref.watch(databaseProvider), ref.watch(clockProvider)),
);

/// The pairing with the server; `null` data means not yet paired.
final serverConfigProvider =
    AsyncNotifierProvider<ServerConfigNotifier, ServerConfig?>(
      ServerConfigNotifier.new,
    );

class ServerConfigNotifier extends AsyncNotifier<ServerConfig?> {
  @override
  Future<ServerConfig?> build() =>
      ref.watch(serverConfigRepositoryProvider).load();

  /// Persists [config]; dependants (api, sync) rebuild with the stored value.
  Future<void> save(ServerConfig config) async {
    final repository = ref.read(serverConfigRepositoryProvider);
    await repository.save(config);
    state = AsyncData(await repository.load());
  }
}

/// `null` while unconfigured.
final apiProvider = Provider<BarTabApi?>((ref) {
  final config = ref.watch(serverConfigProvider).value;
  if (config == null) return null;
  return BarTabApi(client: ref.watch(httpClientProvider), config: config);
});

/// Rebuilt when the config changes: the old service is disposed and a new one
/// is started with the new key. `null` while unconfigured.
final syncServiceProvider = Provider<SyncService?>((ref) {
  final api = ref.watch(apiProvider);
  if (api == null) return null;
  final db = ref.watch(databaseProvider);
  final service = SyncService(
    api: api,
    bookings: ref.watch(bookingRepositoryProvider),
    tabs: ref.watch(tabsRepositoryProvider),
    catalog: ref.watch(catalogRepositoryProvider),
    clock: ref.watch(clockProvider),
    transaction: db.transaction,
  );
  ref.onDispose(service.dispose);
  final interval = ref.watch(syncIntervalProvider);
  if (interval != null) service.start(interval: interval);
  return service;
});

final syncStateProvider = StreamProvider<SyncState>((ref) {
  final service = ref.watch(syncServiceProvider);
  return service?.state ?? const Stream.empty();
});

/// The cached catalog; reloaded after each successful sync.
final catalogProvider = FutureProvider<Catalog?>((ref) {
  ref.watch(syncStateProvider.select((s) => s.value?.lastSuccessAt));
  return ref.watch(catalogRepositoryProvider).cached();
});

/// Server tab plus not-yet-included local bookings of [personId], in cents.
final runningTotalProvider = StreamProvider.family<int, String>((
  ref,
  personId,
) {
  final tabs = ref.watch(tabsRepositoryProvider).watchTab(personId);
  final bookings = ref
      .watch(bookingRepositoryProvider)
      .watchNotIncluded(personId);
  return _combineLatest(
    tabs,
    bookings,
    (tab, local) =>
        runningTotalCents(serverTabCents: tab, localBookings: local),
  );
});

/// Emits [combine] of the latest values once both streams have produced one.
Stream<R> _combineLatest<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A, B) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false;
  var hasB = false;
  void emit() {
    if (hasA && hasB) controller.add(combine(lastA as A, lastB as B));
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen((v) {
        lastA = v;
        hasA = true;
        emit();
      }, onError: controller.addError);
      subB = b.listen((v) {
        lastB = v;
        hasB = true;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}
