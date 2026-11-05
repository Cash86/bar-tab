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

  group('getRankings', () {
    test('getRankings parses overall and persons', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({
          'overall': {'d1': 3},
          'persons': {
            'p1': {'d1': 2},
          },
        });
      });
      final dto = await api.getRankings();
      expect(seen.url.path, '/api/v1/rankings');
      expect(dto.overall, {'d1': 3});
      expect(dto.persons, {
        'p1': {'d1': 2},
      });
    });

    test('getRankings maps 401 to UnauthorisedException', () async {
      final api = _api((r) async => _json({'detail': 'nope'}, 401));
      expect(api.getRankings(), throwsA(isA<UnauthorisedException>()));
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

  group('admin', () {
    final bookingJson = {
      'id': 'b1',
      'person_id': 'p-1',
      'drink_id': 'd1',
      'quantity': 2,
      'unit_price_cents': 150,
      'booked_at': '2026-11-02T18:00:00Z',
      'is_late': false,
      'cancelled_at': null,
    };

    test('login 200 returns the token and posts the pin', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({'token': 't', 'expires_in': 300});
      });
      final result = await api.openAdminSession('1234');
      expect(result, isA<AdminLoggedIn>());
      expect((result as AdminLoggedIn).token, 't');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/admin/session');
      expect(seen.headers['Authorization'], 'Bearer $_key');
      expect(jsonDecode(seen.body), {'pin': '1234'});
    });

    test('login 401 wrong_pin returns AdminWrongPin', () async {
      final api = _api((r) async => _json({'detail': 'wrong_pin'}, 401));
      expect(await api.openAdminSession('0000'), isA<AdminWrongPin>());
    });

    test('login 429 returns AdminLockedOut with retry_after', () async {
      final api = _api(
        (r) async => _json({'detail': 'locked', 'retry_after': 60}, 429),
      );
      final result = await api.openAdminSession('0000');
      expect(result, isA<AdminLockedOut>());
      expect((result as AdminLockedOut).retryAfter, 60);
    });

    test('login 401 invalid_device_key throws UnauthorisedException', () async {
      final api = _api(
        (r) async => _json({'detail': 'invalid_device_key'}, 401),
      );
      expect(
        api.openAdminSession('1234'),
        throwsA(isA<UnauthorisedException>()),
      );
    });

    test('listAdminBookings sends token and person filter', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({
          'bookings': [bookingJson],
        });
      });
      final list = await api.listAdminBookings('t', personId: 'p-1');
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/admin/bookings');
      expect(seen.url.query, 'person_id=p-1');
      expect(seen.headers['X-Admin-Token'], 't');
      expect(seen.headers['Authorization'], 'Bearer $_key');
      expect(list.single.id, 'b1');
      expect(list.single.cancelledAt, isNull);
    });

    test('listAdminBookings without person has no query', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({'bookings': <Object>[]});
      });
      await api.listAdminBookings('t');
      expect(seen.url.hasQuery, isFalse);
    });

    test(
      '401 admin_session_required throws AdminSessionEndedException',
      () async {
        final api = _api(
          (r) async => _json({'detail': 'admin_session_required'}, 401),
        );
        expect(
          api.listAdminBookings('t'),
          throwsA(isA<AdminSessionEndedException>()),
        );
        expect(api.pingAdmin('t'), throwsA(isA<AdminSessionEndedException>()));
      },
    );

    test('401 invalid_device_key throws UnauthorisedException', () async {
      final api = _api(
        (r) async => _json({'detail': 'invalid_device_key'}, 401),
      );
      expect(api.listAdminBookings('t'), throwsA(isA<UnauthorisedException>()));
    });

    test('401 with unreadable body stays UnauthorisedException', () async {
      final api = _api((r) async => http.Response('nope', 401));
      expect(api.pingAdmin('t'), throwsA(isA<UnauthorisedException>()));
    });

    test('pingAdmin GETs admin/ping with the token', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return http.Response('', 204);
      });
      await api.pingAdmin('t');
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/admin/ping');
      expect(seen.headers['X-Admin-Token'], 't');
    });

    test('cancelBooking POSTs and returns the booking', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({...bookingJson, 'cancelled_at': '2026-11-03T10:00:00Z'});
      });
      final b = await api.cancelBooking('t', 'b1');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/admin/bookings/b1/cancel');
      expect(seen.headers['X-Admin-Token'], 't');
      expect(b.cancelledAt, DateTime.utc(2026, 11, 3, 10));
    });

    test('cancelBooking 409 carries the reason', () async {
      final api = _api(
        (r) async => _json({'detail': 'already_cancelled'}, 409),
      );
      await expectLater(
        api.cancelBooking('t', 'b1'),
        throwsA(
          isA<BookingNotCancellableException>().having(
            (e) => e.reason,
            'reason',
            'already_cancelled',
          ),
        ),
      );
    });

    test('cancelBooking 404 carries booking_not_found', () async {
      final api = _api(
        (r) async => _json({'detail': 'booking_not_found'}, 404),
      );
      await expectLater(
        api.cancelBooking('t', 'b1'),
        throwsA(
          isA<BookingNotCancellableException>().having(
            (e) => e.reason,
            'reason',
            'booking_not_found',
          ),
        ),
      );
    });

    test('closeAdminSession sends DELETE with the token', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return http.Response('', 204);
      });
      await api.closeAdminSession('t');
      expect(seen.method, 'DELETE');
      expect(seen.url.path, '/api/v1/admin/session');
      expect(seen.headers['X-Admin-Token'], 't');
    });
  });
}
