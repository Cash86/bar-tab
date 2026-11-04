import 'booking.dart';
import 'catalog.dart';
import 'rankings.dart';
import 'sync_state.dart';

abstract interface class CatalogRepository {
  Future<Catalog?> cached();
  Future<void> save(Catalog catalog);
  Future<void> clear();
}

abstract interface class RankingsRepository {
  Future<void> save(DrinkRankings rankings);

  /// Emits `null` while no rankings have been cached.
  Stream<DrinkRankings?> watch();
}

abstract interface class BookingRepository {
  Future<void> addAll(List<Booking> bookings);

  /// Queued bookings whose hold has expired (or that are not held).
  Future<List<Booking>> queued({int limit});

  /// Deletes [ids] in one transaction if every one is still queued and held
  /// (its `holdUntil` lies in the future); otherwise deletes nothing and
  /// returns `false`.
  Future<bool> undoHeld(Set<String> ids);
  Future<void> applyResults(Map<String, BookingStatus> results);
  Future<void> markIncludedInTabs(Set<String> ids);

  /// Ids of accepted bookings not yet reflected in the cached tabs.
  Future<Set<String>> acceptedNotIncludedIds();
  Stream<List<Booking>> watchNotIncluded(String personId);
  Stream<SyncCounts> watchCounts();
}

abstract interface class TabsRepository {
  Future<void> save(Map<String, int> tabs);
  Stream<int> watchTab(String personId);
}

abstract interface class ServerConfigRepository {
  Future<ServerConfig?> load();
  Future<void> save(ServerConfig config);
}
