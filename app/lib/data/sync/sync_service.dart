import 'dart:async';

import 'package:logging/logging.dart';

import '../../domain/clock.dart';
import '../../domain/repositories.dart';
import '../../domain/sync_state.dart';
import '../api/api_client.dart';
import '../api/mappers.dart';

final _log = Logger('sync');

/// Runs [action] in one database transaction (e.g. `AppDatabase.transaction`).
typedef TransactionRunner =
    Future<void> Function(Future<void> Function() action);

/// Pushes queued bookings, refreshes tabs and the catalog. Local data is
/// never deleted here: failures leave everything in place for the next run.
class SyncService {
  SyncService({
    required this._api,
    required this._bookings,
    required this._tabs,
    required this._catalog,
    required this._clock,
    required this._transaction,
  });

  static const batchSize = 200;
  static const defaultInterval = Duration(seconds: 30);

  final BarTabApi _api;
  final BookingRepository _bookings;
  final TabsRepository _tabs;
  final CatalogRepository _catalog;
  final Clock _clock;
  final TransactionRunner _transaction;

  bool _isUnauthorised = false;
  bool _isOffline = false;
  DateTime? _lastSuccessAt;
  final _flagsChanged = StreamController<void>.broadcast();

  Future<void>? _running;
  bool _disposed = false;
  Timer? _timer;

  /// Broadcast; every listener gets the current state first (once the
  /// booking counts are read), then each change.
  late final Stream<SyncState> state = Stream.multi((listener) {
    SyncCounts? counts;
    SyncState? last;
    void emit() {
      final c = counts;
      if (c == null) return;
      final next = SyncState(
        queued: c.queued,
        failed: c.failed,
        isUnauthorised: _isUnauthorised,
        isOffline: _isOffline,
        lastSuccessAt: _lastSuccessAt,
      );
      if (next == last) return;
      last = next;
      listener.add(next);
    }

    final countsSub = _bookings.watchCounts().listen((c) {
      counts = c;
      emit();
    }, onError: listener.addError);
    final flagsSub = _flagsChanged.stream.listen((_) => emit());
    listener.onCancel = () async {
      await countsSub.cancel();
      await flagsSub.cancel();
    };
  }, isBroadcast: true);

  /// Runs one sync; a call while one is running returns the running one.
  /// After [dispose] it does nothing.
  Future<void> syncNow() {
    if (_disposed) return Future.value();
    return _running ??= _run().whenComplete(() => _running = null);
  }

  /// Syncs now and then every [interval] until [stop].
  void start({Duration interval = defaultInterval}) {
    stop();
    if (_disposed) return;
    _syncInBackground();
    _timer = Timer.periodic(interval, (_) => _syncInBackground());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stops the timer and waits for a running sync; its failure is logged.
  Future<void> dispose() async {
    _disposed = true;
    stop();
    try {
      await _running;
    } on Object catch (e, st) {
      _log.severe('Sync failed during dispose', e, st);
    }
    await _flagsChanged.close();
  }

  void _syncInBackground() {
    syncNow().catchError((Object e, StackTrace st) {
      _log.severe('Sync failed unexpectedly', e, st);
    });
  }

  Future<void> _run() async {
    try {
      await _push();
      await _refreshTabs();
      await _refreshCatalog();
      _setFlags(
        isUnauthorised: false,
        isOffline: false,
        lastSuccessAt: _clock.now(),
      );
    } on UnauthorisedException {
      _setFlags(isUnauthorised: true, isOffline: false);
    } on NetworkException {
      _setFlags(isOffline: true);
    } on ServerException catch (e) {
      _log.warning('Sync stopped: $e');
      _setFlags(isOffline: false);
    } on ContractException catch (e) {
      _log.warning('Sync stopped: $e');
      _setFlags(isOffline: false);
    }
  }

  Future<void> _push() async {
    while (true) {
      final batch = await _bookings.queued(limit: batchSize);
      if (batch.isEmpty) return;
      final results = await _api.postBookings([
        for (final b in batch) bookingToDto(b),
      ]);
      final batchIds = {for (final b in batch) b.id};
      final statuses = {
        for (final r in results)
          if (batchIds.contains(r.id)) r.id: bookingStatusFromResult(r.status),
      };
      // Without progress the same batch would be posted forever.
      if (statuses.isEmpty) {
        throw const ContractException('No result for any posted booking');
      }
      await _bookings.applyResults(statuses);
    }
  }

  Future<void> _refreshTabs() async {
    // Read before the fetch: a booking accepted later may be missing from
    // the server's answer, so it must keep counting locally.
    final included = await _bookings.acceptedNotIncludedIds();
    final tabs = await _api.getTabs();
    // One transaction: tabs that contain a booking never coexist with that
    // booking still counted locally.
    await _transaction(() async {
      await _tabs.save(tabs.tabs);
      await _bookings.markIncludedInTabs(included);
    });
  }

  Future<void> _refreshCatalog() async {
    final cached = await _catalog.cached();
    final fetch = await _api.getCatalog(etag: cached?.etag);
    if (fetch case CatalogUpdated(:final catalog)) {
      try {
        await _catalog.save(catalogFromDto(catalog));
      } on FormatException catch (e) {
        throw ContractException('Invalid catalog: ${e.message}');
      }
    }
  }

  void _setFlags({
    bool? isUnauthorised,
    bool? isOffline,
    DateTime? lastSuccessAt,
  }) {
    _isUnauthorised = isUnauthorised ?? _isUnauthorised;
    _isOffline = isOffline ?? _isOffline;
    _lastSuccessAt = lastSuccessAt ?? _lastSuccessAt;
    if (!_flagsChanged.isClosed) _flagsChanged.add(null);
  }
}
