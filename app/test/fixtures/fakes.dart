import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/data/repositories/server_config_repository_impl.dart';
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
