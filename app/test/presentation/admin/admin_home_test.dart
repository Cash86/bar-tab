import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/admin_home.dart';
import 'package:bar_tab/presentation/admin/design_screen.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/designs.dart';
import '../../fixtures/fakes.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    AppDesign design = AppDesign.standard,
    VoidCallback? onRepair,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(pairedStore()),
          designOverride(design),
        ],
        child: MaterialApp(
          theme: themeFor(design),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            appBar: AppBar(title: const Text('Admin')),
            body: AdminHome(onRepair: onRepair),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the bookings and design tiles with subtitles', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('admin-tile-bookings')), findsOneWidget);
    expect(find.byKey(const Key('admin-tile-design')), findsOneWidget);
    expect(find.text('Buchungen'), findsOneWidget);
    // The deliveries tile carries the same subtitle, so look inside the tile.
    expect(
      find.descendant(
        of: find.byKey(const Key('admin-tile-bookings')),
        matching: find.text('ansehen & stornieren'),
      ),
      findsOneWidget,
    );
    expect(find.text('Standard · Kreidetafel · Bierdeckel'), findsOneWidget);
  });

  testWidgets('the design tile opens the design screen', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('admin-tile-design')));
    await tester.pumpAndSettle();
    expect(find.byType(DesignScreen), findsOneWidget);
  });

  testWidgets('the repair link is disabled without a callback', (tester) async {
    await pump(tester);
    expect(find.text('Server neu koppeln'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('admin-repair'))).enabled,
      isFalse,
    );
  });

  testWidgets('the repair link calls the callback', (tester) async {
    var called = 0;
    await pump(tester, onRepair: () => called++);
    await tester.tap(find.byKey(const Key('admin-repair')));
    expect(called, 1);
  });

  forEachDesign((design) {
    testWidgets('fits 1280x720 without overflow', (tester) async {
      await pump(tester, design: design);
      expect(tester.takeException(), isNull);
      // The home sits below the app bar: every tile and the link must lie
      // inside the visible body, not just inside the window.
      final body = tester.getRect(find.byType(AdminHome));
      final tiles = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('admin-tile-'),
      );
      expect(tiles, findsWidgets);
      // All tiles fit without scrolling.
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position
            .maxScrollExtent,
        0,
      );
      for (final tile in tiles.evaluate()) {
        final rect = tester.getRect(find.byWidget(tile.widget));
        expect(body.contains(rect.topLeft), isTrue);
        expect(rect.bottom, lessThanOrEqualTo(body.bottom));
        expect(rect.right, lessThanOrEqualTo(body.right));
      }
      expect(
        tester.getRect(find.byKey(const Key('admin-repair'))).bottom,
        lessThanOrEqualTo(body.bottom),
      );
    });
  });
}
