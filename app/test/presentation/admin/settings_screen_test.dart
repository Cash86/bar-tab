import 'dart:convert';

import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/settings_screen.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
  late List<String> recipients;
  late String? valuation;
  late Map<String, Object?>? lastSettlement;
  late String resendStatus;
  late bool resendFails;

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    recipients = ['a@example.org'];
    valuation = null;
    resendStatus = 'sent';
    resendFails = false;
    lastSettlement = {
      'period_id': 'p1',
      'closed_at': '2026-11-03T20:15:00Z',
      'mail_status': 'failed',
    };
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (path.endsWith('admin/settings') && r.method == 'GET') {
        return _json({
          'recipients': recipients,
          'valuation_tier_id': valuation,
          'effective_valuation_tier_id': valuation ?? 't1',
          'last_settlement': lastSettlement,
        });
      }
      if (path.endsWith('settings/recipients') && r is http.Request) {
        final list =
            ((jsonDecode(r.body) as Map<String, dynamic>)['recipients'] as List)
                .cast<String>();
        if (list.any((a) => !a.contains('@'))) {
          return _json({'detail': 'invalid_email'}, 422);
        }
        recipients = list;
        return http.Response('', 204);
      }
      if (path.endsWith('settings/valuation-tier') && r is http.Request) {
        valuation =
            (jsonDecode(r.body) as Map<String, dynamic>)['tier_id'] as String;
        return http.Response('', 204);
      }
      if (path.endsWith('settlement/resend')) {
        if (resendFails) return _json({'detail': 'x'}, 500);
        return _json({'mail_status': resendStatus});
      }
      if (path.endsWith('/tabs')) {
        return _json({
          'period_started_at': '2026-11-01T00:00:00Z',
          'tabs': <String, int>{},
        });
      }
      if (path.endsWith('/catalog')) return catalogResponse();
      if (path.endsWith('/rankings')) {
        return _json({
          'overall': <String, int>{},
          'persons': <String, Object>{},
        });
      }
      return _json({});
    };
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(pairedStore()),
          httpClientProvider.overrideWithValue(server.client),
          clockProvider.overrideWithValue(clock),
          catalogProvider.overrideWith(
            (ref) async => const Catalog(
              tiers: [
                PriceTier(id: 't1', name: 'Aktive', sortOrder: 1),
                PriceTier(id: 't2', name: 'Gäste', sortOrder: 2),
              ],
              persons: [],
              groups: [],
              drinks: [],
              etag: 'e',
            ),
          ),
          rankingsProvider.overrideWith((ref) => Stream.value(null)),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: BarTabTheme.data,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const NameListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-gear')));
    await tester.pumpAndSettle();
    for (final d in '1234'.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-tile-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  Future<void> add(WidgetTester tester, String address) async {
    await tester.enterText(find.byKey(const Key('recipient-field')), address);
    await tester.tap(find.byKey(const Key('recipient-add')));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the recipients and the effective tier', (tester) async {
    await open(tester);
    expect(find.text('a@example.org'), findsOneWidget);
    expect(find.text('Schwund bewerten mit'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('valuation-tier')),
        matching: find.text('Aktive'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('adds a recipient and saves the whole list', (tester) async {
    await open(tester);
    await add(tester, ' b@example.org ');
    expect(recipients, ['a@example.org', 'b@example.org']);
    expect(find.text('b@example.org'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('recipient-field')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('an invalid address shows an error and is not listed', (
    tester,
  ) async {
    await open(tester);
    await add(tester, 'nope');
    expect(find.text('Ungültige E-Mail-Adresse'), findsOneWidget);
    expect(find.byKey(const Key('recipient-nope')), findsNothing);
    expect(recipients, ['a@example.org']);
  });

  testWidgets('removes a recipient', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('recipient-remove-a@example.org')));
    await tester.pumpAndSettle();
    expect(recipients, isEmpty);
    expect(find.text('a@example.org'), findsNothing);
  });

  testWidgets('choosing a tier saves it', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('valuation-tier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gäste').last);
    await tester.pumpAndSettle();
    expect(valuation, 't2');
  });

  testWidgets('shows the last settlement and re-sends the PDF', (tester) async {
    await open(tester);
    expect(find.text('Letzte Abrechnung'), findsOneWidget);
    expect(find.textContaining('03.11.'), findsOneWidget);
    expect(find.text('Mail fehlgeschlagen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settlement-resend')));
    await tester.pumpAndSettle();
    expect(find.text('PDF verschickt'), findsOneWidget);
    expect(find.text('Mail fehlgeschlagen'), findsNothing);
  });

  testWidgets('a failing re-send shows an error', (tester) async {
    resendFails = true;
    await open(tester);
    await tester.tap(find.byKey(const Key('settlement-resend')));
    await tester.pumpAndSettle();
    expect(find.text('Senden nicht möglich'), findsOneWidget);
    expect(find.text('Mail fehlgeschlagen'), findsOneWidget);
  });

  testWidgets('without a settlement the section is hidden', (tester) async {
    lastSettlement = null;
    await open(tester);
    expect(find.text('Letzte Abrechnung'), findsNothing);
    expect(find.byKey(const Key('settlement-resend')), findsNothing);
  });
}
