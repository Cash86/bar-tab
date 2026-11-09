import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

import '../data/api/api_client.dart';
import '../data/api/mappers.dart';
import '../data/db/database.dart';
import '../data/repositories/booking_repository_impl.dart';
import '../data/repositories/catalog_repository_impl.dart';
import '../data/repositories/drift_config_store.dart';
import '../data/repositories/local_pin_store.dart';
import '../data/repositories/rankings_repository_impl.dart';
import '../data/repositories/server_config_repository_impl.dart';
import '../data/repositories/tabs_repository_impl.dart';
import '../data/sync/sync_service.dart';
import '../domain/catalog.dart';
import '../domain/clock.dart';
import '../domain/rankings.dart';
import '../domain/repositories.dart';
import '../domain/sync_state.dart';
import 'admin/count_draft.dart';

final clockProvider = Provider<Clock>((ref) => SystemClock());

/// Must be overridden with the opened database (see `main.dart`).
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final configStoreProvider = Provider<ConfigStore>(
  (ref) => DriftConfigStore(ref.watch(databaseProvider)),
);

final countDraftStoreProvider = Provider<CountDraftStore>(
  (ref) => CountDraftStore(ref.watch(configStoreProvider)),
);

/// Hash of the admin PIN kept on the tablet for offline re-pairing.
final localPinStoreProvider = Provider<LocalPinStore>(
  (ref) => LocalPinStore(ref.watch(configStoreProvider)),
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
  (ref) => ServerConfigRepositoryImpl(ref.watch(configStoreProvider)),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepositoryImpl(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  ),
);

final rankingsRepositoryProvider = Provider<RankingsRepository>(
  (ref) => RankingsRepositoryImpl(
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
  /// [onStored] runs after the write and before the rebuild, so the new sync
  /// service never races it.
  Future<void> save(
    ServerConfig config, {
    Future<void> Function()? onStored,
  }) async {
    final repository = ref.read(serverConfigRepositoryProvider);
    await repository.save(config);
    await onStored?.call();
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
    rankings: ref.watch(rankingsRepositoryProvider),
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

/// The cached drink rankings; `null` until the first sync delivered them.
final rankingsProvider = StreamProvider<DrinkRankings?>(
  (ref) => ref.watch(rankingsRepositoryProvider).watch(),
);

/// Server tab plus not-yet-included local bookings of [personId], in cents,
/// from one query (never an intermediate value during a sync).
final runningTotalProvider = StreamProvider.family<int, String>(
  (ref, personId) =>
      ref.watch(tabsRepositoryProvider).watchRunningTotal(personId),
);

enum PairingResult { success, unauthorised, unreachable }

final _pairingLog = Logger('pairing');

class Pairing {
  Pairing(this._ref);

  final Ref _ref;

  /// Checks [config] against the server, then stores catalog and config.
  /// Never throws; on any failure neither is left changed. With [repair] the
  /// tabs and rankings cached from the old server are dropped once the new
  /// config is stored; bookings are never touched.
  Future<PairingResult> pair(ServerConfig config, {bool repair = false}) async {
    final catalogs = _ref.read(catalogRepositoryProvider);
    final api = BarTabApi(
      client: _ref.read(httpClientProvider),
      config: config,
    );
    try {
      final fetch = await api.getCatalog();
      if (fetch is! CatalogUpdated) return PairingResult.unreachable;
      final catalog = catalogFromDto(fetch.catalog);
      final previous = await catalogs.cached();
      await catalogs.save(catalog);
      try {
        await _ref
            .read(serverConfigProvider.notifier)
            .save(config, onStored: repair ? _clearServerCaches : null);
      } on Object {
        // Config is saved last, so only the catalog needs undoing.
        if (previous == null) {
          await catalogs.clear();
        } else {
          await catalogs.save(previous);
        }
        rethrow;
      }
      return PairingResult.success;
    } on UnauthorisedException {
      return PairingResult.unauthorised;
    } on Object catch (e, st) {
      _pairingLog.warning('Pairing failed', e, st);
      return PairingResult.unreachable;
    }
  }

  /// Best effort: the next sync replaces both caches anyway.
  Future<void> _clearServerCaches() async {
    try {
      await _ref.read(tabsRepositoryProvider).clear();
      await _ref.read(rankingsRepositoryProvider).clear();
    } on Object catch (e, st) {
      _pairingLog.warning('Old server caches not cleared', e, st);
    }
  }
}

final pairingProvider = Provider<Pairing>(Pairing.new);
