import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bar_tab/data/api/api_client.dart';
import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key = 'secret-device-key';

Map<String, dynamic> _catalogJson() => {
  'price_tiers': [
    {'id': 't1', 'name': 'Standard', 'sort_order': 1},
  ],
  'persons': [
    {
      'id': 'p1',
      'name': 'Jörg',
      'price_tier_id': 't1',
      'is_hidden': false,
      'is_collective': false,
      'is_active': true,
    },
  ],
  'groups': [
    {'id': 'g1', 'name': 'Alkoholfrei', 'sort_order': 1, 'color': '#112233'},
  ],
  'drinks': [
    {
      'id': 'd1',
      'name': 'Faßbrause',
      'group_id': 'g1',
      'crate_size': 20,
      'sort_order': 1,
      'is_hidden': false,
      'is_active': true,
      'prices': {'t1': 150},
    },
  ],
  'etag': 'abc123',
};

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

BarTabApi _api(
  MockClientHandler handler, {
  String baseUrl = 'https://bar.example.test',
  Duration timeout = const Duration(seconds: 10),
}) => BarTabApi(
  client: MockClient(handler),
  config: ServerConfig(baseUrl: baseUrl, deviceKey: _key),
  timeout: timeout,
);

final _booking = BookingInDto(
  id: 'b1',
  personId: 'p1',
  drinkId: 'd1',
  quantity: 2,
  unitPriceCents: 150,
  bookedAt: DateTime.utc(2026, 11, 2, 18),
);

void main() {
  group('getCatalog', () {
    test(
      'sends bearer header, path, and no If-None-Match without etag',
      () async {
        late http.Request seen;
        final api = _api((r) async {
          seen = r;
          return _json(_catalogJson());
        });
        final result = await api.getCatalog();
        expect(seen.method, 'GET');
        expect(seen.url.toString(), 'https://bar.example.test/api/v1/catalog');
        expect(seen.headers['Authorization'], 'Bearer $_key');
        expect(seen.headers.containsKey('If-None-Match'), isFalse);
        expect(result, isA<CatalogUpdated>());
      },
    );

    test('200 decodes umlauts and returns the etag', () async {
      final api = _api((r) async => _json(_catalogJson()));
      final result = await api.getCatalog() as CatalogUpdated;
      expect(result.catalog.etag, 'abc123');
      expect(result.catalog.persons.single.name, 'Jörg');
      expect(result.catalog.drinks.single.name, 'Faßbrause');
    });

    test(
      'sends quoted If-None-Match and maps 304 to CatalogUnchanged',
      () async {
        late http.Request seen;
        final api = _api((r) async {
          seen = r;
          return http.Response('', 304);
        });
        final result = await api.getCatalog(etag: 'abc123');
        expect(seen.headers['If-None-Match'], '"abc123"');
        expect(result, isA<CatalogUnchanged>());
      },
    );
  });

  group('postBookings', () {
    test('posts the bookings envelope and returns results in order', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({
          'results': [
            {'id': 'b1', 'status': 'accepted'},
            {'id': 'b2', 'status': 'rejected', 'reason': 'unknown_drink'},
          ],
        });
      });
      final results = await api.postBookings([_booking]);
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/bookings');
      expect(seen.headers['Authorization'], 'Bearer $_key');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body.keys, ['bookings']);
      final first = (body['bookings'] as List).single as Map<String, dynamic>;
      expect(first['id'], 'b1');
      expect(first['unit_price_cents'], 150);
      expect(results.map((r) => r.id), ['b1', 'b2']);
      expect(results[1].status, BookingResultStatus.rejected);
      expect(results[1].reason, BookingRejectReason.unknownDrink);
    });
  });

  group('getTabs', () {
    test('requests /api/v1/tabs and parses the body', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({
          'period_started_at': '2026-11-01T00:00:00Z',
          'tabs': {'p1': 300},
        });
      });
      final tabs = await api.getTabs();
      expect(seen.url.path, '/api/v1/tabs');
      expect(seen.headers['Authorization'], 'Bearer $_key');
      expect(tabs.tabs, {'p1': 300});
    });
  });

  group('errors', () {
    test('401 -> UnauthorisedException', () async {
      final api = _api((r) async => _json({'detail': 'nope'}, 401));
      expect(api.getTabs(), throwsA(isA<UnauthorisedException>()));
    });

    test('503 -> ServerException(503)', () async {
      final api = _api((r) async => http.Response('down', 503));
      expect(
        api.getCatalog(),
        throwsA(isA<ServerException>().having((e) => e.status, 'status', 503)),
      );
    });

    test('unexpected 4xx -> ServerException', () async {
      final api = _api((r) async => _json({'detail': 'bad'}, 422));
      expect(
        api.postBookings([_booking]),
        throwsA(isA<ServerException>().having((e) => e.status, 'status', 422)),
      );
    });

    test('SocketException -> NetworkException', () async {
      final api = _api((r) async => throw const SocketException('boom'));
      expect(api.getTabs(), throwsA(isA<NetworkException>()));
    });

    test('ClientException -> NetworkException', () async {
      final api = _api((r) async => throw http.ClientException('boom'));
      expect(api.getTabs(), throwsA(isA<NetworkException>()));
    });

    test('HandshakeException -> NetworkException', () async {
      final api = _api((r) async => throw const HandshakeException('tls'));
      expect(api.getTabs(), throwsA(isA<NetworkException>()));
    });

    test('timeout -> NetworkException', () async {
      final api = _api(
        (r) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 20),
      );
      expect(api.getTabs(), throwsA(isA<NetworkException>()));
    });

    test('HTML body on 200 -> ContractException', () async {
      final api = _api((r) async => http.Response('<html></html>', 200));
      expect(api.getCatalog(), throwsA(isA<ContractException>()));
    });

    test('wrong JSON shape on 200 -> ContractException', () async {
      final api = _api((r) async => _json({'unexpected': true}));
      expect(api.getTabs(), throwsA(isA<ContractException>()));
    });

    test('messages never contain the device key', () async {
      final api = _api((r) async => throw http.ClientException('boom', r.url));
      try {
        await api.getTabs();
        fail('expected throw');
      } on ApiException catch (e) {
        expect(e.toString(), isNot(contains(_key)));
        expect(e.message, isNot(contains(_key)));
      }
    });
  });

  group('base URL', () {
    for (final base in [
      'https://bar.example.test',
      'https://bar.example.test/',
    ]) {
      test('"$base" yields a single slash before /api', () async {
        late Uri seen;
        final api = _api((r) async {
          seen = r.url;
          return _json({
            'period_started_at': '2026-11-01T00:00:00Z',
            'tabs': <String, int>{},
          });
        }, baseUrl: base);
        await api.getTabs();
        expect(seen.toString(), 'https://bar.example.test/api/v1/tabs');
      });
    }
  });
}
