import 'package:bar_tab/app.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fakes.dart';

void main() {
  late AppDatabase db;
  late FakeApiServer server;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    server = FakeApiServer();
  });

  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, FakeSecureStore store) async {
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
        ],
        child: const BarTabApp(),
      ),
    );
  }

  testWidgets('shows a progress indicator while the config loads', (
    tester,
  ) async {
    await pumpApp(tester, FakeSecureStore());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('no config leads to the setup screen', (tester) async {
    await pumpApp(tester, FakeSecureStore());
    await tester.pumpAndSettle();
    expect(find.text('Tablet einrichten'), findsOneWidget);
    expect(find.text('Wer trinkt?'), findsNothing);
  });

  testWidgets('saved config leads to the name list', (tester) async {
    await pumpApp(tester, pairedStore());
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.text('Tablet einrichten'), findsNothing);
  });
}
