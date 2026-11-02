import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/data/repositories/server_config_repository_impl.dart';
import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'catalog_fixture.dart';

/// In-memory stand-in for the platform secure storage.
class FakeSecureStore implements SecureStore {
  FakeSecureStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  /// When set, every write throws it (simulates a keystore failure).
  Object? writeError;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    final error = writeError;
    if (error != null) throw error;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A secure store that already holds a pairing.
FakeSecureStore pairedStore({
  String baseUrl = 'https://bar.example',
  String deviceKey = 'key-a',
}) => FakeSecureStore({
  ServerConfigRepositoryImpl.baseUrlKey: baseUrl,
  ServerConfigRepositoryImpl.deviceKeyKey: deviceKey,
});

/// Scripted bar-tab server behind a [MockClient].
class FakeApiServer {
  /// Requests received, in order.
  final requests = <http.BaseRequest>[];

  /// Answers every request with this; override per test.
  Future<http.Response> Function(http.BaseRequest request) respond =
      (_) async => catalogResponse();

  /// `Authorization` header of each request, in order.
  List<String?> get authHeaders => [
    for (final r in requests) r.headers['Authorization'],
  ];

  late final MockClient client = MockClient.streaming((request, body) async {
    requests.add(request);
    final response = await respond(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  });
}

http.Response catalogResponse() => http.Response(
  jsonEncode(catalogFixtureJson),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// In-memory booking store; `watchNotIncluded` emits the current list on
/// listen and after every write.
class FakeBookingRepository implements BookingRepository {
  final bookings = <Booking>[];

  /// When set, `addAll` throws it (simulates a database failure).
  Object? addAllError;

  /// When set, `addAll` waits for it before writing (a slow database).
  Completer<void>? addAllGate;

  final _changed = StreamController<void>.broadcast();

  @override
  Future<void> addAll(List<Booking> bookings) async {
    await addAllGate?.future;
    final error = addAllError;
    if (error != null) throw error;
    this.bookings.addAll(bookings);
    _changed.add(null);
  }

  @override
  Stream<List<Booking>> watchNotIncluded(String personId) {
    List<Booking> current() => [
      for (final b in bookings)
        if (b.personId == personId && !b.includedInTabs) b,
    ];
    return Stream.multi((listener) {
      listener.add(current());
      final sub = _changed.stream.listen((_) => listener.add(current()));
      listener.onCancel = sub.cancel;
    });
  }

  @override
  Future<List<Booking>> queued({int limit = 200}) async => [
    for (final b in bookings)
      if (b.status == BookingStatus.queued) b,
  ].take(limit).toList();

  @override
  Future<void> applyResults(Map<String, BookingStatus> results) async {}

  @override
  Future<void> markIncludedInTabs(Set<String> ids) async {}

  @override
  Future<Set<String>> acceptedNotIncludedIds() async => {};

  @override
  Stream<SyncCounts> watchCounts() => const Stream.empty();
}

/// Server tabs held in memory.
class FakeTabsRepository implements TabsRepository {
  FakeTabsRepository([Map<String, int>? tabs]) : tabs = {...?tabs};

  final Map<String, int> tabs;

  @override
  Future<void> save(Map<String, int> tabs) async => this.tabs
    ..clear()
    ..addAll(tabs);

  @override
  Stream<int> watchTab(String personId) => Stream.value(tabs[personId] ?? 0);
}

/// Counts `syncNow` calls; everything else is unsupported.
class FakeSyncService implements SyncService {
  int syncNowCalls = 0;

  /// When set, `syncNow` completes with this error.
  Object? syncError;

  @override
  Future<void> syncNow() async {
    syncNowCalls++;
    final error = syncError;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
