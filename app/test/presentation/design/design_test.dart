import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/common/sync_indicator.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/drinks/order_bar.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/designs.dart';
import '../../fixtures/fakes.dart';

void main() {
  group('AppDesign.parse', () {
    test('maps stored names to designs', () {
      expect(AppDesign.parse('standard'), AppDesign.standard);
      expect(AppDesign.parse('kreidetafel'), AppDesign.kreidetafel);
      expect(AppDesign.parse('bierdeckel'), AppDesign.bierdeckel);
    });

    test('falls back to standard for null or unknown values', () {
      expect(AppDesign.parse(null), AppDesign.standard);
      expect(AppDesign.parse('x'), AppDesign.standard);
    });

    test('storageKey is the name and round-trips', () {
      for (final d in AppDesign.values) {
        expect(d.storageKey, d.name);
        expect(AppDesign.parse(d.storageKey), d);
      }
    });
  });

  group('appDesignProvider', () {
    late FakeConfigStore store;

    ProviderContainer containerFor(AppDesign initial) {
      final container = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(store),
          designOverride(initial),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() => store = FakeConfigStore());

    test('starts in the initial design', () {
      expect(
        containerFor(AppDesign.bierdeckel).read(appDesignProvider),
        AppDesign.bierdeckel,
      );
    });

    test('select writes the store and updates the state', () async {
      final container = containerFor(AppDesign.standard);
      await container
          .read(appDesignProvider.notifier)
          .select(AppDesign.kreidetafel);
      expect(store.values[kDesignConfigKey], 'kreidetafel');
      expect(container.read(appDesignProvider), AppDesign.kreidetafel);
    });

    test('a failed write keeps the old design', () async {
      final container = containerFor(AppDesign.standard);
      store.writeError = StateError('disk full');
      await expectLater(
        container.read(appDesignProvider.notifier).select(AppDesign.bierdeckel),
        throwsStateError,
      );
      expect(container.read(appDesignProvider), AppDesign.standard);
    });

    test('a fresh scope started from the store keeps the choice', () async {
      await containerFor(
        AppDesign.standard,
      ).read(appDesignProvider.notifier).select(AppDesign.bierdeckel);
      final restarted = containerFor(await loadDesign(store));
      expect(restarted.read(appDesignProvider), AppDesign.bierdeckel);
    });

    test('loadDesign reads standard from an empty store', () async {
      expect(await loadDesign(store), AppDesign.standard);
    });
  });

  group('themeFor', () {
    test('standard is today\'s theme plus the tokens', () {
      final theme = themeFor(AppDesign.standard);
      expect(theme.scaffoldBackgroundColor, BarTabTheme.bottle);
      expect(theme.canvasColor, BarTabTheme.bottle);
      expect(theme.cardColor, BarTabTheme.bottle2);
      expect(theme.colorScheme, BarTabTheme.data.colorScheme);
      expect(theme.textTheme, BarTabTheme.data.textTheme);
      expect(theme.copyWith(extensions: const []), BarTabTheme.data);
      expect(theme.extension<DesignTokens>(), tokensFor(AppDesign.standard));
    });

    test('standard tokens are today\'s constants', () {
      final t = tokensFor(AppDesign.standard);
      expect(t.background, BarTabTheme.bottle);
      expect(t.surface, BarTabTheme.bottle2);
      expect(t.surfaceHigh, BarTabTheme.bottle3);
      expect(t.text, BarTabTheme.paper);
      expect(t.muted, BarTabTheme.muted);
      expect(t.accent, BarTabTheme.collectiveAccent);
      expect(t.onAccent, BarTabTheme.bottle);
      expect(t.tierPalette, BarTabTheme.tierPalette);
      expect(t.bodyFont, BarTabTheme.fontFamily);
      expect(t.displayFont, BarTabTheme.fontFamily);
      for (var i = 0; i < 9; i++) {
        expect(t.tierColor(i), BarTabTheme.tierColor(i));
      }
    });

    test('kreidetafel is a chalkboard in Caveat', () {
      final theme = themeFor(AppDesign.kreidetafel);
      final t = theme.extension<DesignTokens>()!;
      expect(t.displayFont, 'Caveat');
      expect(t.background, const Color(0xFF232724));
      expect(t.backgroundHighlight, const Color(0xFF3A403C));
      expect(t.frame, const Color(0xFF7A5534));
      expect(t.text, const Color(0xFFF4F1E8));
      expect(t.accent, const Color(0xFFF7D774));
      expect(theme.scaffoldBackgroundColor, t.background);
    });

    test('bierdeckel is a green counter with slab-serif coasters', () {
      final theme = themeFor(AppDesign.bierdeckel);
      final t = theme.extension<DesignTokens>()!;
      expect(t.displayFont, 'Alfa Slab One');
      expect(t.bodyFont, 'Barlow Condensed');
      expect(t.background, const Color(0xFF17322A));
      expect(t.backgroundHighlight, const Color(0xFF2F5A47));
      expect(t.surface, const Color(0xFFF3E7CF));
      expect(t.accent, const Color(0xFF7A1F1F));
      expect(t.highlight, const Color(0xFFD9A441));
      expect(theme.scaffoldBackgroundColor, t.background);
    });

    forEachDesign((design) {
      test('tier palette cycles and theme uses the body font', () {
        final t = tokensFor(design);
        expect(t.tierPalette, hasLength(4));
        expect(t.tierPalette.toSet(), hasLength(4));
        expect(t.tierColor(5), t.tierColor(1));
        expect(themeFor(design).textTheme.bodyMedium?.fontFamily, t.bodyFont);
      });
    });

    test('the new designs do not reuse the standard palette', () {
      final standard = tokensFor(AppDesign.standard).tierPalette;
      expect(tokensFor(AppDesign.kreidetafel).tierPalette, isNot(standard));
      expect(tokensFor(AppDesign.bierdeckel).tierPalette, isNot(standard));
    });
  });

  testWidgets('DesignTokens.of falls back to standard without the extension', (
    tester,
  ) async {
    late DesignTokens tokens;
    await tester.pumpWidget(
      MaterialApp(
        theme: BarTabTheme.data,
        home: Builder(
          builder: (context) {
            tokens = DesignTokens.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(tokens, tokensFor(AppDesign.standard));
  });

  test('every bundled font licence is registered', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFontLicenses();
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }
    expect(
      packages,
      containsAll(['Archivo', 'Caveat', 'Alfa Slab One', 'Barlow Condensed']),
    );
  });

  group('shared widgets take the design colours', () {
    Future<void> pumpIn(WidgetTester tester, AppDesign design, Widget child) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              syncStateProvider.overrideWith(
                (ref) => Stream.value(
                  const SyncState(
                    queued: 2,
                    failed: 0,
                    isUnauthorised: false,
                    isOffline: false,
                  ),
                ),
              ),
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
              home: Scaffold(body: child),
            ),
          ),
        );

    forEachDesign((design) {
      testWidgets('sync indicator is muted', (tester) async {
        await pumpIn(tester, design, const SyncIndicator());
        await tester.pump();
        final text = tester.widget<Text>(find.text('2 Buchungen warten'));
        expect(text.style?.color, tokensFor(design).muted);
      });

      testWidgets('order bar is text-coloured with background ink', (
        tester,
      ) async {
        final tokens = tokensFor(design);
        await pumpIn(
          tester,
          design,
          OrderBar(
            summary: '1× Lager',
            totalCents: 120,
            secondsLeft: 5,
            countdownRun: 0,
            onDiscard: () {},
            onDone: () {},
          ),
        );
        final bar = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(OrderBar),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(bar.color, tokens.text);
        expect(
          tester.widget<Text>(find.text('1× Lager')).style?.color,
          tokens.background,
        );
      });
    });
  });
}
