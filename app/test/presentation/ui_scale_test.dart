import 'package:bar_tab/app.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/presentation/drinks/drink_selection_screen.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/setup/setup_screen.dart';
import 'package:bar_tab/presentation/ui_scale.dart';
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

  final catalog = Catalog(
    tiers: const [PriceTier(id: 't1', name: 'Members', sortOrder: 1)],
    persons: [
      for (var i = 0; i < 12; i++)
        Person(
          id: 'p$i',
          name: 'Name ${i.toString().padLeft(2, '0')}',
          priceTierId: 't1',
          isHidden: false,
          isCollective: false,
          isActive: true,
        ),
    ],
    groups: const [],
    drinks: const [],
    etag: 'e',
  );

  Future<void> pumpApp(
    WidgetTester tester,
    Size size, {
    bool paired = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          configStoreProvider.overrideWithValue(
            paired ? pairedStore() : FakeConfigStore(),
          ),
          httpClientProvider.overrideWithValue(server.client),
          syncIntervalProvider.overrideWithValue(null),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          catalogProvider.overrideWith((ref) async => catalog),
          // Drift streams leave timers behind inside widget tests.
          for (var i = 0; i < 12; i++)
            runningTotalProvider('p$i').overrideWithValue(const AsyncLoading()),
        ],
        child: const BarTabApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  MediaQueryData mq(WidgetTester tester, Type screen) =>
      MediaQuery.of(tester.element(find.byType(screen)));

  group('uiScaleFor', () {
    test('never scales down, caps at 2', () {
      expect(uiScaleFor(1024), 1.0);
      expect(uiScaleFor(1280), 1.0);
      expect(uiScaleFor(1920), 1.5);
      expect(uiScaleFor(3840), 2.0);
    });
  });

  testWidgets('1920x1080 renders as 1280x720 logical px', (tester) async {
    await pumpApp(tester, const Size(1920, 1080));
    expect(mq(tester, NameListScreen).size, const Size(1280, 720));
  });

  testWidgets('1920x1080 shows 3 tiles per row', (tester) async {
    await pumpApp(tester, const Size(1920, 1080));
    final tops = [
      for (var i = 0; i < 4; i++) tester.getTopLeft(find.text('Name 0$i')).dy,
    ];
    expect(tops[0], tops[1]);
    expect(tops[1], tops[2]);
    expect(tops[3], greaterThan(tops[2]));
  });

  testWidgets('tap at the visually scaled position hits the tile', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1920, 1080));
    final center = tester.getCenter(find.text('Name 05'));
    // Visually scaled: beyond the 1280x720 logical area.
    expect(center.dx > 1280 || center.dy > 720, isTrue);
    // Visually scaled: well beyond the 1280x720 logical area.

    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final screen = tester.widget<DrinkSelectionScreen>(
      find.byType(DrinkSelectionScreen),
    );
    expect(screen.personId, 'p5');
  });

  testWidgets('1280x800 is unscaled', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    expect(mq(tester, NameListScreen).size, const Size(1280, 800));
  });

  testWidgets('1024x600 stays at scale 1', (tester) async {
    await pumpApp(tester, const Size(1024, 600));
    expect(mq(tester, NameListScreen).size, const Size(1024, 600));
  });

  testWidgets('viewInsets are divided by the scale', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await pumpApp(tester, const Size(1920, 1080), paired: false);
    expect(mq(tester, SetupScreen).viewInsets.bottom, 200);
  });
}
