import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bar_tab/data/api/api_client.dart';
import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:fake_async/fake_async.dart';
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

  group('admin master data, deliveries and PIN', () {
    final personJson = {
      'id': 'p1',
      'name': 'Jörg',
      'price_tier_id': 't1',
      'is_hidden': false,
      'is_collective': false,
      'is_active': true,
    };
    final drinkJson = {
      'id': 'd1',
      'name': 'Faßbrause',
      'group_id': 'g1',
      'crate_size': 20,
      'sort_order': 1,
      'is_hidden': false,
      'is_active': true,
      'prices': {'t1': 150},
    };
    final groupJson = {
      'id': 'g1',
      'name': 'Alkoholfrei',
      'sort_order': 1,
      'color': '#112233',
    };
    final tierJson = {'id': 't1', 'name': 'Standard', 'sort_order': 1};
    final deliveryJson = {
      'id': 'dl1',
      'drink_id': 'd1',
      'quantity': 3,
      'created_at': '2026-11-02T18:00:00Z',
      'cancelled_at': null,
    };

    /// Runs [call] against a MockClient answering [body] and returns what the
    /// client sent together with the result.
    Future<(http.Request, T)> run<T>(
      Future<T> Function(BarTabApi api) call, {
      Object? body,
      int status = 200,
    }) async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return body == null ? http.Response('', status) : _json(body, status);
      });
      final result = await call(api);
      return (seen, result);
    }

    void expectAdmin(http.Request r, String method, String path) {
      expect(r.method, method);
      expect(r.url.path, '/api/v1/$path');
      expect(r.headers['X-Admin-Token'], 't');
    }

    test('createPerson POSTs the body and parses the person', () async {
      final (r, p) = await run(
        (a) => a.createPerson(
          't',
          const PersonWriteDto(
            name: 'Jörg',
            priceTierId: 't1',
            isHidden: false,
            isCollective: false,
          ),
        ),
        body: personJson,
        status: 201,
      );
      expectAdmin(r, 'POST', 'admin/persons');
      expect(jsonDecode(r.body), {
        'name': 'Jörg',
        'price_tier_id': 't1',
        'is_hidden': false,
        'is_collective': false,
      });
      expect(p.id, 'p1');
    });

    test('updatePerson PUTs the body including is_active', () async {
      final (r, p) = await run(
        (a) => a.updatePerson(
          't',
          'p1',
          const PersonWriteDto(
            name: 'Jörg',
            priceTierId: 't1',
            isHidden: false,
            isCollective: false,
            isActive: false,
          ),
        ),
        body: personJson,
      );
      expectAdmin(r, 'PUT', 'admin/persons/p1');
      expect((jsonDecode(r.body) as Map)['is_active'], false);
      expect(p.name, 'Jörg');
    });

    test('createDrink POSTs the body and parses the drink', () async {
      final (r, d) = await run(
        (a) => a.createDrink(
          't',
          const DrinkWriteDto(
            name: 'Faßbrause',
            groupId: 'g1',
            crateSize: 20,
            isHidden: false,
            isKeg: true,
            prices: {'t1': 150},
          ),
        ),
        body: drinkJson,
        status: 201,
      );
      expectAdmin(r, 'POST', 'admin/drinks');
      expect(jsonDecode(r.body), {
        'name': 'Faßbrause',
        'group_id': 'g1',
        'crate_size': 20,
        'is_hidden': false,
        'is_keg': true,
        'prices': {'t1': 150},
      });
      expect(d.prices, {'t1': 150});
    });

    test('updateDrink PUTs the body including is_active', () async {
      final (r, d) = await run(
        (a) => a.updateDrink(
          't',
          'd1',
          const DrinkWriteDto(
            name: 'Faßbrause',
            groupId: 'g1',
            crateSize: 20,
            isHidden: true,
            isKeg: false,
            prices: {'t1': 150},
            isActive: true,
          ),
        ),
        body: drinkJson,
      );
      expectAdmin(r, 'PUT', 'admin/drinks/d1');
      expect((jsonDecode(r.body) as Map)['is_active'], true);
      expect(d.id, 'd1');
    });

    test('createGroup POSTs name and colour', () async {
      final (r, g) = await run(
        (a) => a.createGroup(
          't',
          const GroupWriteDto(name: 'Alkoholfrei', color: '#112233'),
        ),
        body: groupJson,
        status: 201,
      );
      expectAdmin(r, 'POST', 'admin/groups');
      expect(jsonDecode(r.body), {'name': 'Alkoholfrei', 'color': '#112233'});
      expect(g.color, '#112233');
    });

    test('updateGroup PUTs name and colour', () async {
      final (r, g) = await run(
        (a) => a.updateGroup(
          't',
          'g1',
          const GroupWriteDto(name: 'Alkoholfrei', color: '#112233'),
        ),
        body: groupJson,
      );
      expectAdmin(r, 'PUT', 'admin/groups/g1');
      expect(g.id, 'g1');
    });

    test('deleteGroup sends DELETE', () async {
      final (r, _) = await run((a) => a.deleteGroup('t', 'g1'), status: 204);
      expectAdmin(r, 'DELETE', 'admin/groups/g1');
    });

    test('createPriceTier POSTs the name', () async {
      final (r, t) = await run(
        (a) => a.createPriceTier('t', 'Standard'),
        body: tierJson,
        status: 201,
      );
      expectAdmin(r, 'POST', 'admin/price-tiers');
      expect(jsonDecode(r.body), {'name': 'Standard'});
      expect(t.name, 'Standard');
    });

    test('updatePriceTier PUTs the name', () async {
      final (r, t) = await run(
        (a) => a.updatePriceTier('t', 't1', 'Standard'),
        body: tierJson,
      );
      expectAdmin(r, 'PUT', 'admin/price-tiers/t1');
      expect(jsonDecode(r.body), {'name': 'Standard'});
      expect(t.id, 't1');
    });

    test('deletePriceTier sends DELETE', () async {
      final (r, _) = await run(
        (a) => a.deletePriceTier('t', 't1'),
        status: 204,
      );
      expectAdmin(r, 'DELETE', 'admin/price-tiers/t1');
    });

    test('reorderGroups PUTs the ids', () async {
      final (r, _) = await run(
        (a) => a.reorderGroups('t', ['g2', 'g1']),
        status: 204,
      );
      expectAdmin(r, 'PUT', 'admin/order/groups');
      expect(jsonDecode(r.body), {
        'ids': ['g2', 'g1'],
      });
    });

    test('reorderPriceTiers PUTs the ids', () async {
      final (r, _) = await run(
        (a) => a.reorderPriceTiers('t', ['t2', 't1']),
        status: 204,
      );
      expectAdmin(r, 'PUT', 'admin/order/price-tiers');
      expect(jsonDecode(r.body), {
        'ids': ['t2', 't1'],
      });
    });

    test('reorderDrinks PUTs the ids to the group path', () async {
      final (r, _) = await run(
        (a) => a.reorderDrinks('t', 'g1', ['d2', 'd1']),
        status: 204,
      );
      expectAdmin(r, 'PUT', 'admin/order/drinks/g1');
      expect(jsonDecode(r.body), {
        'ids': ['d2', 'd1'],
      });
    });

    test('createDeliveries POSTs the batch and parses the answer', () async {
      final (r, list) = await run(
        (a) => a.createDeliveries('t', [
          const DeliveryInDto(id: 'dl1', drinkId: 'd1', quantity: 3),
        ]),
        body: {
          'deliveries': [deliveryJson],
        },
        status: 201,
      );
      expectAdmin(r, 'POST', 'admin/deliveries');
      expect(jsonDecode(r.body), {
        'deliveries': [
          {'id': 'dl1', 'drink_id': 'd1', 'quantity': 3},
        ],
      });
      expect(list.single.quantity, 3);
      expect(list.single.cancelledAt, isNull);
    });

    test('listDeliveries GETs the deliveries', () async {
      final (r, list) = await run(
        (a) => a.listDeliveries('t'),
        body: {
          'deliveries': [deliveryJson],
        },
      );
      expectAdmin(r, 'GET', 'admin/deliveries');
      expect(list.single.createdAt, DateTime.utc(2026, 11, 2, 18));
    });

    test('cancelDelivery POSTs and returns the delivery', () async {
      final (r, d) = await run(
        (a) => a.cancelDelivery('t', 'dl1'),
        body: {...deliveryJson, 'cancelled_at': '2026-11-03T10:00:00Z'},
      );
      expectAdmin(r, 'POST', 'admin/deliveries/dl1/cancel');
      expect(d.cancelledAt, DateTime.utc(2026, 11, 3, 10));
    });

    test('cancelDelivery 409 and 404 become RejectedException', () async {
      for (final (status, detail) in [
        (409, 'already_cancelled'),
        (404, 'not_found'),
      ]) {
        final api = _api((r) async => _json({'detail': detail}, status));
        await expectLater(
          api.cancelDelivery('t', 'dl1'),
          throwsA(
            isA<RejectedException>().having((e) => e.detail, 'detail', detail),
          ),
        );
      }
    });

    test('409 name_taken becomes RejectedException', () async {
      final api = _api((r) async => _json({'detail': 'name_taken'}, 409));
      await expectLater(
        api.createPriceTier('t', 'Standard'),
        throwsA(
          isA<RejectedException>().having(
            (e) => e.detail,
            'detail',
            'name_taken',
          ),
        ),
      );
    });

    test('422 with a list detail becomes RejectedException unknown', () async {
      final api = _api(
        (r) async => _json({
          'detail': [
            {'msg': 'bad'},
          ],
        }, 422),
      );
      await expectLater(
        api.reorderGroups('t', ['g1']),
        throwsA(
          isA<RejectedException>().having((e) => e.detail, 'detail', 'unknown'),
        ),
      );
    });

    test('422 invalid_name carries its detail', () async {
      final api = _api((r) async => _json({'detail': 'invalid_name'}, 422));
      await expectLater(
        api.createGroup('t', const GroupWriteDto(name: '', color: '#000000')),
        throwsA(
          isA<RejectedException>().having(
            (e) => e.detail,
            'detail',
            'invalid_name',
          ),
        ),
      );
    });

    test('401 admin_session_required ends the admin session', () async {
      final api = _api(
        (r) async => _json({'detail': 'admin_session_required'}, 401),
      );
      await expectLater(
        api.deleteGroup('t', 'g1'),
        throwsA(isA<AdminSessionEndedException>()),
      );
    });

    test('changeAdminPin 204 returns PinChanged and sends both pins', () async {
      final (r, result) = await run(
        (a) => a.changeAdminPin('t', '1234', '5678'),
        status: 204,
      );
      expectAdmin(r, 'PUT', 'admin/pin');
      expect(jsonDecode(r.body), {'current_pin': '1234', 'new_pin': '5678'});
      expect(result, isA<PinChanged>());
    });

    test('changeAdminPin 403 wrong_pin returns PinWrong', () async {
      final api = _api((r) async => _json({'detail': 'wrong_pin'}, 403));
      expect(await api.changeAdminPin('t', '0', '5678'), isA<PinWrong>());
    });

    test('changeAdminPin 429 returns PinLocked with retry_after', () async {
      final api = _api(
        (r) async => _json({'detail': 'locked', 'retry_after': 30}, 429),
      );
      final result = await api.changeAdminPin('t', '0', '5678');
      expect(result, isA<PinLocked>());
      expect((result as PinLocked).retryAfter, 30);
    });

    test(
      'changeAdminPin 401 admin_session_required ends the session',
      () async {
        final api = _api(
          (r) async => _json({'detail': 'admin_session_required'}, 401),
        );
        await expectLater(
          api.changeAdminPin('t', '1', '2'),
          throwsA(isA<AdminSessionEndedException>()),
        );
      },
    );
  });

  group('inventory, settlement and settings', () {
    final lineJson = {
      'drink_id': 'd1',
      'name': 'Faßbrause',
      'group_id': 'g1',
      'opening': 10,
      'delivered': 20,
      'booked': 5,
      'expected': 25,
      'counted': 24,
      'shrinkage': 1,
      'value_cents': 3600,
      'has_price': true,
    };
    final groupLineJson = {
      'group_id': 'g1',
      'name': 'Alkoholfrei',
      'opening': 10,
      'delivered': 20,
      'booked': 5,
      'expected': 25,
      'counted': 24,
      'shrinkage': 1,
      'value_cents': 3600,
      'has_price': true,
    };
    final closeJson = {
      'period_id': 'pr1',
      'closed_at': '2026-11-09T20:00:00Z',
      'mail_status': 'pending',
    };

    Future<(http.Request, T)> run<T>(
      Future<T> Function(BarTabApi api) call, {
      Object? body,
      int status = 200,
    }) async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return body == null ? http.Response('', status) : _json(body, status);
      });
      final result = await call(api);
      return (seen, result);
    }

    void expectAdmin(http.Request r, String method, String path) {
      expect(r.method, method);
      expect(r.url.path, '/api/v1/$path');
      expect(r.headers['X-Admin-Token'], 't');
    }

    test('getStock GETs the stock', () async {
      final (r, s) = await run(
        (a) => a.getStock('t'),
        body: {
          'period_id': 'pr1',
          'opening_count_allowed': true,
          'drinks': [
            {
              'drink_id': 'd1',
              'name': 'Faßbrause',
              'group_id': 'g1',
              'group_name': 'Alkoholfrei',
              'crate_size': 20,
              'expected': 7,
            },
          ],
        },
      );
      expectAdmin(r, 'GET', 'admin/stock');
      expect(s.periodId, 'pr1');
      expect(s.openingCountAllowed, isTrue);
      expect(s.drinks.single.groupName, 'Alkoholfrei');
      expect(s.drinks.single.expected, 7);
    });

    test('reviewSettlement POSTs the counts and parses the review', () async {
      final (r, v) = await run(
        (a) => a.reviewSettlement('t', {'d1': 24}),
        body: {
          'token': 'rt',
          'valuation_tier_name': 'Standard',
          'drinks': [lineJson],
          'groups': [groupLineJson],
          'persons_total_cents': 3000,
          'hidden_total_cents': 600,
          'grand_total_cents': 3600,
          'shrinkage_total_cents': 150,
        },
      );
      expectAdmin(r, 'POST', 'admin/settlement/review');
      expect(jsonDecode(r.body), {
        'counts': [
          {'drink_id': 'd1', 'quantity': 24},
        ],
      });
      expect(v.token, 'rt');
      expect(v.drinks.single.shrinkage, 1);
      expect(v.groups.single.valueCents, 3600);
      expect(v.grandTotalCents, 3600);
    });

    test('closeSettlement POSTs token and counts, 201 parses', () async {
      final (r, c) = await run(
        (a) => a.closeSettlement('t', 'rt', {'d1': 24}),
        body: closeJson,
        status: 201,
      );
      expectAdmin(r, 'POST', 'admin/settlement/close');
      expect(jsonDecode(r.body), {
        'token': 'rt',
        'counts': [
          {'drink_id': 'd1', 'quantity': 24},
        ],
      });
      expect(c.periodId, 'pr1');
      expect(c.closedAt, DateTime.utc(2026, 11, 9, 20));
      expect(c.mailStatus, MailStatus.pending);
    });

    test('closeSettlement 200 (replay) is a success too', () async {
      final (_, c) = await run(
        (a) => a.closeSettlement('t', 'rt', {}),
        body: {...closeJson, 'mail_status': 'sent'},
      );
      expect(c.mailStatus, MailStatus.sent);
    });

    test('closeSettlement waits 60 s, other calls the client timeout', () {
      fakeAsync((async) {
        // Answers after 30 s, like a close that mails synchronously.
        final api = _api(
          (r) => Future.delayed(
            const Duration(seconds: 30),
            () => _json(closeJson, 201),
          ),
        );
        Object? reviewError;
        api
            .reviewSettlement('t', {})
            .then<void>((_) {}, onError: (Object e) => reviewError = e);
        SettlementCloseDto? closed;
        api.closeSettlement('t', 'rt', {}).then((c) => closed = c);
        async.elapse(const Duration(seconds: 31));
        expect(reviewError, isA<NetworkException>());
        expect(closed?.periodId, 'pr1');

        Object? closeError;
        final slow = _api(
          (r) => Future.delayed(
            const Duration(seconds: 61),
            () => _json(closeJson, 201),
          ),
        );
        slow
            .closeSettlement('t', 'rt', {})
            .then<void>((_) {}, onError: (Object e) => closeError = e);
        async.elapse(const Duration(seconds: 62));
        expect(closeError, isA<NetworkException>());
      });
    });

    test('resendSettlement waits like the close (it mails synchronously)', () {
      fakeAsync((async) {
        final api = _api(
          (r) => Future.delayed(
            const Duration(seconds: 30),
            () => _json({'mail_status': 'sent'}),
          ),
        );
        MailStatus? status;
        Object? error;
        api
            .resendSettlement('t')
            .then((s) => status = s, onError: (Object e) => error = e);
        async.elapse(const Duration(seconds: 31));
        expect(error, isNull);
        expect(status, MailStatus.sent);
      });
    });

    test('closeSettlement 409 stale_review and already_settled', () async {
      Future<void> expectThrows(String detail, Matcher matcher) async {
        final api = _api((r) async => _json({'detail': detail}, 409));
        await expectLater(api.closeSettlement('t', 'rt', {}), throwsA(matcher));
      }

      await expectThrows('stale_review', isA<StaleReviewException>());
      await expectThrows('already_settled', isA<AlreadySettledException>());
    });

    test('settlement 422 codes become RejectedException', () async {
      for (final detail in [
        'missing_count',
        'unknown_reference',
        'invalid_quantity',
      ]) {
        final api = _api((r) async => _json({'detail': detail}, 422));
        await expectLater(
          api.reviewSettlement('t', {'d1': -1}),
          throwsA(
            isA<RejectedException>().having((e) => e.detail, 'detail', detail),
          ),
        );
      }
    });

    test('recordOpeningCount POSTs the counts, 204', () async {
      final (r, _) = await run(
        (a) => a.recordOpeningCount('t', {'d1': 4, 'd2': 0}),
        status: 204,
      );
      expectAdmin(r, 'POST', 'admin/opening-count');
      expect(jsonDecode(r.body), {
        'counts': [
          {'drink_id': 'd1', 'quantity': 4},
          {'drink_id': 'd2', 'quantity': 0},
        ],
      });
    });

    test('recordOpeningCount 409 is a RejectedException', () async {
      final api = _api((r) async => _json({'detail': 'not_allowed'}, 409));
      await expectLater(
        api.recordOpeningCount('t', {}),
        throwsA(
          isA<RejectedException>().having(
            (e) => e.detail,
            'detail',
            'not_allowed',
          ),
        ),
      );
    });

    test('getSettings GETs and parses nulls and last settlement', () async {
      final (r, s) = await run(
        (a) => a.getSettings('t'),
        body: {
          'recipients': ['a@example.test'],
          'valuation_tier_id': null,
          'effective_valuation_tier_id': 't1',
          'last_settlement': closeJson,
        },
      );
      expectAdmin(r, 'GET', 'admin/settings');
      expect(s.recipients, ['a@example.test']);
      expect(s.valuationTierId, isNull);
      expect(s.effectiveValuationTierId, 't1');
      expect(s.lastSettlement!.periodId, 'pr1');
    });

    test('setRecipients PUTs the list, 204', () async {
      final (r, _) = await run(
        (a) => a.setRecipients('t', ['a@example.test']),
        status: 204,
      );
      expectAdmin(r, 'PUT', 'admin/settings/recipients');
      expect(jsonDecode(r.body), {
        'recipients': ['a@example.test'],
      });
    });

    test('setRecipients 422 invalid_email', () async {
      final api = _api((r) async => _json({'detail': 'invalid_email'}, 422));
      await expectLater(
        api.setRecipients('t', ['nope']),
        throwsA(isA<InvalidEmailException>()),
      );
    });

    test('setValuationTier PUTs the tier id, 204', () async {
      final (r, _) = await run(
        (a) => a.setValuationTier('t', 't2'),
        status: 204,
      );
      expectAdmin(r, 'PUT', 'admin/settings/valuation-tier');
      expect(jsonDecode(r.body), {'tier_id': 't2'});
    });

    test(
      'resendSettlement POSTs without body and returns the status',
      () async {
        final (r, m) = await run(
          (a) => a.resendSettlement('t'),
          body: {'mail_status': 'failed'},
        );
        expectAdmin(r, 'POST', 'admin/settlement/resend');
        expect(r.body, isEmpty);
        expect(m, MailStatus.failed);
      },
    );

    test('resendSettlement 404 no_settlement', () async {
      final api = _api((r) async => _json({'detail': 'no_settlement'}, 404));
      await expectLater(
        api.resendSettlement('t'),
        throwsA(
          isA<RejectedException>().having(
            (e) => e.detail,
            'detail',
            'no_settlement',
          ),
        ),
      );
    });

    test('401 admin_session_required ends the session', () async {
      final api = _api(
        (r) async => _json({'detail': 'admin_session_required'}, 401),
      );
      await expectLater(
        api.getStock('t'),
        throwsA(isA<AdminSessionEndedException>()),
      );
    });
  });
}
