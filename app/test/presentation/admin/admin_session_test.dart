import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/data/api/api_client.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/presentation/admin/admin_session.dart';
import 'package:bar_tab/presentation/kiosk.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../fixtures/fakes.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late FakeApiServer server;
  late FixedClock clock;
  late ProviderContainer container;

  setUp(() async {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 12));
    container = ProviderContainer(
      overrides: [
        configStoreProvider.overrideWithValue(pairedStore()),
        httpClientProvider.overrideWithValue(server.client),
        clockProvider.overrideWithValue(clock),
      ],
    );
    await container.read(serverConfigProvider.future);
    container.listen(adminSessionProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  AdminSessionNotifier notifier() =>
      container.read(adminSessionProvider.notifier);
  String? token() => container.read(adminSessionProvider);

  void loginOk() => server.respond = (r) async {
    if (r.method == 'POST') return _json({'token': 't1', 'expires_in': 300});
    return _json({});
  };

  Future<void> loggedIn() async {
    loginOk();
    await notifier().login('1234');
    server.requests.clear();
  }

  List<String> adminCalls() => [
    for (final r in server.requests) '${r.method} ${r.url.path}',
  ];

  test('login stores the token', () async {
    loginOk();
    final result = await notifier().login('1234');
    expect(result, (AdminLoginResult.success, null));
    expect(token(), 't1');
  });

  test('wrong pin and lockout keep no token', () async {
    server.respond = (r) async => _json({'detail': 'wrong_pin'}, 401);
    expect(await notifier().login('0000'), (AdminLoginResult.wrongPin, null));
    expect(token(), isNull);

    server.respond = (r) async =>
        _json({'detail': 'locked', 'retry_after': 60}, 429);
    expect(await notifier().login('0000'), (AdminLoginResult.locked, 60));
    expect(token(), isNull);
  });

  test('offline login is unreachable', () async {
    server.respond = (r) async => throw http.ClientException('down');
    expect(await notifier().login('1234'), (
      AdminLoginResult.unreachable,
      null,
    ));
    expect(token(), isNull);
  });

  test('any other API failure on login is unreachable', () async {
    final answers = <http.Response>[
      _json({'detail': 'boom'}, 500),
      _json({'detail': 'not_authorised'}, 401),
      http.Response('not json', 200),
    ];
    for (final answer in answers) {
      server.respond = (r) async => answer;
      expect(await notifier().login('1234'), (
        AdminLoginResult.unreachable,
        null,
      ));
      expect(token(), isNull);
    }
  });

  test('a logout during login wins and revokes the late token', () async {
    final gate = Completer<http.Response>();
    server.respond = (r) async {
      if (r.method == 'POST') return gate.future;
      return _json({});
    };

    final login = notifier().login('1234');
    await Future<void>.delayed(Duration.zero);
    await notifier().logout();
    gate.complete(_json({'token': 't1', 'expires_in': 300}));
    await login;
    await Future<void>.delayed(Duration.zero);

    expect(token(), isNull);
    expect(adminCalls(), [
      'POST /api/v1/admin/session',
      'DELETE /api/v1/admin/session',
    ]);
    expect(server.requests.last.headers['X-Admin-Token'], 't1');
  });

  test(
    'logout clears the token before the server answers and sends DELETE',
    () async {
      await loggedIn();
      final gate = Completer<http.Response>();
      server.respond = (r) => gate.future;

      final done = notifier().logout();
      expect(token(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(adminCalls(), ['DELETE /api/v1/admin/session']);
      expect(server.requests.single.headers['X-Admin-Token'], 't1');
      gate.complete(_json({}));
      await done;
    },
  );

  test('logout while offline still clears the token', () async {
    await loggedIn();
    server.respond = (r) async => throw http.ClientException('down');
    await notifier().logout();
    expect(token(), isNull);
  });

  test('interaction pings at most once per 60 s', () async {
    await loggedIn();
    notifier().onInteraction();
    clock.advance(const Duration(seconds: 30));
    notifier().onInteraction();
    clock.advance(const Duration(seconds: 31));
    notifier().onInteraction();
    await Future<void>.delayed(Duration.zero);
    expect(adminCalls(), ['GET /api/v1/admin/ping']);
    expect(server.requests.single.headers['X-Admin-Token'], 't1');

    // The ping itself reset the clock.
    clock.advance(const Duration(seconds: 30));
    notifier().onInteraction();
    await Future<void>.delayed(Duration.zero);
    expect(adminCalls(), hasLength(1));
  });

  test('a request resets the keep-alive clock', () async {
    await loggedIn();
    clock.advance(const Duration(seconds: 50));
    await notifier().run((api, t) => api.pingAdmin(t));
    server.requests.clear();
    clock.advance(const Duration(seconds: 50));
    notifier().onInteraction();
    await Future<void>.delayed(Duration.zero);
    expect(server.requests, isEmpty);
  });

  test('session ended on a call clears the token', () async {
    await loggedIn();
    server.respond = (r) async =>
        _json({'detail': 'admin_session_required'}, 401);
    await expectLater(
      notifier().run((api, t) => api.listAdminBookings(t)),
      throwsA(isA<AdminSessionEndedException>()),
    );
    expect(token(), isNull);
  });

  test('session ended on a ping clears the token', () async {
    await loggedIn();
    server.respond = (r) async =>
        _json({'detail': 'admin_session_required'}, 401);
    clock.advance(kAdminKeepAliveInterval);
    notifier().onInteraction();
    await Future<void>.delayed(Duration.zero);
    expect(token(), isNull);
  });

  test('a failed ping is ignored and keeps the token', () async {
    await loggedIn();
    server.respond = (r) async => throw http.ClientException('down');
    clock.advance(kAdminKeepAliveInterval);
    notifier().onInteraction();
    await Future<void>.delayed(Duration.zero);
    expect(token(), 't1');
  });
  test(
    'keep-alive interval plus idle stays below the server session limit',
    () {
      // Server limit: ADMIN_SESSION_IDLE_SECONDS in server/bartab/security.py.
      expect(
        kAdminKeepAliveInterval + kIdleTimeout < const Duration(seconds: 300),
        isTrue,
      );
    },
  );
}
