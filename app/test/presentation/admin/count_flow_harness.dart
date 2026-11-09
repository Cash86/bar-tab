import 'dart:convert';

import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/kiosk.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../fixtures/fakes.dart';

const countFlowIdle = Duration(seconds: 10);

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

typedef Handler = Future<http.Response> Function(http.Request request);

/// Stock as `GET /admin/stock` answers it: Pils (crate 20) and a hidden keg
/// in "Bier", Wasser (crate 12) in "Alkoholfrei".
Map<String, dynamic> stockJson({bool openingAllowed = true}) => {
  'opening_count_allowed': openingAllowed,
  'drinks': [
    {
      'drink_id': 'd1',
      'name': 'Pils',
      'group_id': 'g1',
      'group_name': 'Bier',
      'crate_size': 20,
      'expected': 50,
    },
    {
      'drink_id': 'd2',
      'name': 'Fass',
      'group_id': 'g1',
      'group_name': 'Bier',
      'crate_size': 1,
      'expected': 30,
    },
    {
      'drink_id': 'd3',
      'name': 'Wasser',
      'group_id': 'g2',
      'group_name': 'Alkoholfrei',
      'crate_size': 12,
      'expected': 10,
    },
  ],
};

Map<String, dynamic> _line(
  String id,
  String name,
  int expected,
  int counted,
  int value, {
  bool hasPrice = true,
  String? drinkId,
}) => {
  if (drinkId != null) 'drink_id': drinkId else 'group_id': id,
  if (drinkId != null) 'group_id': id,
  'name': name,
  'opening': 0,
  'delivered': 0,
  'booked': 0,
  'expected': expected,
  'counted': counted,
  'shrinkage': expected - counted,
  'value_cents': value,
  'has_price': hasPrice,
};

/// A review answer; [token] and [pilsCounted] let a test tell two apart.
Map<String, dynamic> reviewJson({
  String token = 'rev-1',
  int pilsCounted = 43,
}) => {
  'token': token,
  'valuation_tier_name': 'Aktive',
  'drinks': [
    _line(
      'g1',
      'Pils',
      50,
      pilsCounted,
      (50 - pilsCounted) * 120,
      drinkId: 'd1',
    ),
    _line('g1', 'Fass', 30, 30, 0, hasPrice: false, drinkId: 'd2'),
    _line('g2', 'Wasser', 10, 12, -160, drinkId: 'd3'),
  ],
  'groups': [
    _line(
      'g1',
      'Bier',
      80,
      30 + pilsCounted,
      (50 - pilsCounted) * 120,
      hasPrice: false,
    ),
    _line('g2', 'Alkoholfrei', 10, 12, -160),
  ],
  'persons_total_cents': 12345,
  'hidden_total_cents': 500,
  'grand_total_cents': 12845,
  'shrinkage_total_cents': (50 - pilsCounted) * 120 - 160,
};

/// Admin login, stock, review, close and opening count against a fake
/// server, with a sync service whose flush result a test sets.
class CountFlowHarness {
  CountFlowHarness() {
    server.respond = (r) async {
      final path = r.url.path;
      if (path.endsWith('admin/session')) {
        if (r.method == 'POST') {
          return jsonResponse({'token': 't1', 'expires_in': 300});
        }
        return http.Response('', 204);
      }
      if (path.endsWith('admin/stock')) return onStock(r as http.Request);
      if (path.endsWith('admin/settlement/review')) {
        return onReview(r as http.Request);
      }
      if (path.endsWith('admin/settlement/close')) {
        return onClose(r as http.Request);
      }
      if (path.endsWith('admin/opening-count')) {
        return onOpening(r as http.Request);
      }
      if (path.endsWith('/tabs')) {
        return jsonResponse({
          'period_started_at': '2026-11-01T00:00:00Z',
          'tabs': <String, int>{},
        });
      }
      if (path.endsWith('/catalog')) return catalogResponse();
      if (path.endsWith('/rankings')) {
        return jsonResponse({
          'overall': <String, int>{},
          'persons': <String, Object>{},
        });
      }
      return jsonResponse({});
    };
  }

  final server = FakeApiServer();
  final clock = FixedClock(DateTime.utc(2026, 11, 9, 21));
  final sync = FakeSyncService();
  final store = pairedStore();

  Handler onStock = (_) async => jsonResponse(stockJson());
  Handler onReview = (_) async => jsonResponse(reviewJson());
  Handler onClose = (_) async => jsonResponse({
    'period_id': 'p1',
    'closed_at': '2026-11-09T21:00:00Z',
    'mail_status': 'sent',
  }, 201);
  Handler onOpening = (_) async => http.Response('', 204);

  List<http.Request> requestsTo(String suffix) => [
    for (final r in server.requests.whereType<http.Request>())
      if (r.url.path.endsWith(suffix)) r,
  ];

  /// The counts of [request] as drink id to units.
  Map<String, int> countsOf(http.Request request) => {
    for (final c
        in ((jsonDecode(request.body) as Map<String, dynamic>)['counts']
                as List)
            .cast<Map<String, dynamic>>())
      c['drink_id'] as String: c['quantity'] as int,
  };

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(store),
          httpClientProvider.overrideWithValue(server.client),
          clockProvider.overrideWithValue(clock),
          idleTimeoutProvider.overrideWithValue(countFlowIdle),
          catalogProvider.overrideWith(
            (ref) async => const Catalog(
              tiers: [],
              persons: [],
              groups: [],
              drinks: [],
              etag: 'e',
            ),
          ),
          rankingsProvider.overrideWith((ref) => Stream.value(null)),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          syncServiceProvider.overrideWithValue(sync),
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
  }

  Future<void> login(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('admin-gear')));
    await tester.pumpAndSettle();
    for (final d in '1234'.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
  }

  /// Pumps the app, logs in and opens the admin tile [tile].
  Future<void> open(WidgetTester tester, String tile) async {
    await pump(tester);
    await login(tester);
    await tester.tap(find.byKey(Key('admin-tile-$tile')));
    await tester.pumpAndSettle();
  }

  Future<void> typeDigits(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
  }

  /// Selects the row of [drinkId], then types crates and/or units.
  Future<void> enter(
    WidgetTester tester,
    String drinkId, {
    String crates = '',
    String units = '',
  }) async {
    await tester.tap(find.byKey(Key('qty-row-$drinkId')));
    await tester.pump();
    await typeDigits(tester, crates);
    if (units.isNotEmpty) {
      final chip = find.byKey(const Key('qty-chip-units'));
      if (chip.evaluate().isNotEmpty) await tester.tap(chip);
      await tester.pump();
      await typeDigits(tester, units);
    }
  }

  /// Pils 2 K + 3 = 43, Fass 30, Wasser 1 K = 12.
  Future<void> enterAll(WidgetTester tester) async {
    await enter(tester, 'd1', crates: '2', units: '3');
    await enter(tester, 'd2', units: '30');
    await enter(tester, 'd3', crates: '1');
  }
}
