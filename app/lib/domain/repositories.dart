import 'booking.dart';
import 'catalog.dart';
import 'sync_state.dart';

abstract interface class CatalogRepository {
  Future<Catalog?> cached();
  Future<void> save(Catalog catalog);
}

abstract interface class BookingRepository {
  Future<void> addAll(List<Booking> bookings);
  Future<List<Booking>> queued({int limit});
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
