import 'dart:async';
import 'dart:io';

import 'package:bar_tab/app.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/server_config_repository_impl.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../fixtures/fakes.dart';

void main() {
  late FakeSecureStore store;
  late FakeApiServer server;
  late AppDatabase db;

  setUp(() {
    store = FakeSecureStore();
    server = FakeApiServer();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secureStoreProvider.overrideWithValue(store),
          httpClientProvider.overrideWithValue(server.client),
          syncIntervalProvider.overrideWithValue(null),
          // The name list watches this; drift streams leave timers behind
          // when the tree is disposed inside a widget test.
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const BarTabApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(
    WidgetTester tester, {
    String url = 'https://bar.example/',
    String key = 'secret-key',
  }) async {
    await tester.enterText(find.byKey(const Key('setup-url')), url);
    await tester.enterText(find.byKey(const Key('setup-key')), key);
    await tester.tap(find.text('Verbinden'));
    await tester.pump();
  }

  testWidgets('shows the setup form with obscured key', (tester) async {
    await pumpApp(tester);
    expect(find.text('Tablet einrichten'), findsOneWidget);
    expect(find.text('Server-Adresse'), findsOneWidget);
    expect(find.text('Geräteschlüssel'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('setup-key')));
    expect(field.obscureText, isTrue);
  });

  for (final url in ['', 'bar.example', 'ftp://bar.example', 'https://']) {
    testWidgets('rejects invalid address "$url" without a request', (
      tester,
    ) async {
      await pumpApp(tester);
      await submit(tester, url: url);
      await tester.pumpAndSettle();
      expect(find.text('Adresse ungültig'), findsOneWidget);
      expect(server.requests, isEmpty);
    });
  }

  testWidgets('401 shows the key error and saves nothing', (tester) async {
    server.respond = (_) async => http.Response('{}', 401);
    await pumpApp(tester);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Geräteschlüssel ungültig'), findsOneWidget);
    expect(store.values, isEmpty);
    expect(find.text('Verbinden'), findsOneWidget);
  });

  testWidgets('network failure shows the unreachable error', (tester) async {
    server.respond = (_) async => throw const SocketException('down');
    await pumpApp(tester);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    expect(store.values, isEmpty);
  });

  testWidgets('other server errors show the unreachable error', (tester) async {
    server.respond = (_) async => http.Response('boom', 500);
    await pumpApp(tester);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
  });

  testWidgets('success saves trimmed config and catalog, opens name list', (
    tester,
  ) async {
    await pumpApp(tester);
    await submit(tester);
    await tester.pumpAndSettle();

    expect(store.values, {
      ServerConfigRepositoryImpl.baseUrlKey: 'https://bar.example',
      ServerConfigRepositoryImpl.deviceKeyKey: 'secret-key',
    });
    expect(server.requests, hasLength(1));
    expect(server.requests.single.method, 'GET');
    expect(
      server.requests.single.url.toString(),
      'https://bar.example/api/v1/catalog',
    );
    expect(server.authHeaders.single, 'Bearer secret-key');
    final cached = await tester.runAsync(
      () => db.select(db.catalogCache).get(),
    );
    expect(cached, hasLength(1));
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.text('Tablet einrichten'), findsNothing);
  });

  testWidgets('storage failure shows an error, re-enables, leaves no state', (
    tester,
  ) async {
    store.writeError = StateError('keystore broken');
    await pumpApp(tester);
    await submit(tester);
    await tester.pumpAndSettle();

    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(store.values, isEmpty);
    final cached = await tester.runAsync(
      () => db.select(db.catalogCache).get(),
    );
    expect(cached, isEmpty);
    expect(find.text('Tablet einrichten'), findsOneWidget);
  });

  testWidgets('button is disabled while the request is pending', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    server.respond = (_) => gate.future;
    await pumpApp(tester);
    await submit(tester);

    final button = find.byType(FilledButton);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(server.requests, hasLength(1));

    gate.complete(catalogResponse());
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
  });
}
