import 'dart:convert';

import 'package:bar_tab/domain/sync_state.dart';
import 'package:bar_tab/presentation/admin/admin_home.dart';
import 'package:bar_tab/presentation/admin/inventory_screen.dart';
import 'package:bar_tab/presentation/admin/settlement_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'count_flow_harness.dart';

void main() {
  late CountFlowHarness h;

  setUp(() => h = CountFlowHarness());

  Finder reviewButton() => find.byKey(const Key('count-review'));
  Finder saveButton() => find.byKey(const Key('count-save'));
  bool enabled(WidgetTester tester, Finder f) =>
      tester.widget<ButtonStyleButton>(f).enabled;

  Map<String, dynamic>? draft(String mode) {
    final raw = h.store.values['count_draft_$mode'];
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  testWidgets('admin home shows the settlement and opening count tiles', (
    tester,
  ) async {
    await h.pump(tester);
    await h.login(tester);
    Finder inTile(String name, String text) => find.descendant(
      of: find.byKey(Key('admin-tile-$name')),
      matching: find.text(text),
    );
    expect(inTile('settlement', 'Inventur & Abrechnung'), findsOneWidget);
    expect(inTile('settlement', 'zählen, prüfen, abschließen'), findsOneWidget);
    expect(inTile('opening', 'Anfangsbestand'), findsOneWidget);
    expect(inTile('opening', 'nur vor der ersten Abrechnung'), findsOneWidget);
  });

  group('settlement start', () {
    testWidgets('an unreachable server stops the flow', (tester) async {
      h.sync.flushResult = const FlushResult(
        reachable: false,
        pending: 0,
        failed: 0,
      );
      await h.open(tester, 'settlement');
      expect(h.sync.flushCalls, 1);
      expect(find.text('Server nicht erreichbar'), findsOneWidget);
      expect(find.byKey(const Key('qty-row-d1')), findsNothing);
      expect(h.requestsTo('admin/stock'), isEmpty);
    });

    testWidgets('a throwing flush counts as unreachable', (tester) async {
      h.sync.flushError = StateError('boom');
      await h.open(tester, 'settlement');
      expect(find.text('Server nicht erreichbar'), findsOneWidget);
      expect(find.byKey(const Key('qty-row-d1')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pending bookings stop the flow', (tester) async {
      h.sync.flushResult = const FlushResult(
        reachable: true,
        pending: 2,
        failed: 0,
      );
      await h.open(tester, 'settlement');
      expect(
        find.text('2 Buchungen noch nicht gesendet – Abrechnung nicht möglich'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qty-row-d1')), findsNothing);
      expect(h.requestsTo('admin/stock'), isEmpty);
    });

    testWidgets('failed bookings warn, the flow continues', (tester) async {
      h.sync.flushResult = const FlushResult(
        reachable: true,
        pending: 0,
        failed: 3,
      );
      await h.open(tester, 'settlement');
      expect(
        find.text('3 fehlgeschlagene Buchungen werden nicht abgerechnet'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qty-row-d1')), findsOneWidget);
    });

    testWidgets('a failing stock load says so', (tester) async {
      h.onStock = (_) async => throw http.ClientException('down');
      await h.open(tester, 'settlement');
      expect(find.text('Server nicht erreichbar'), findsOneWidget);
      expect(find.byKey(const Key('qty-row-d1')), findsNothing);
    });
  });

  group('count step', () {
    testWidgets('lists the stock drinks by group, hidden keg included', (
      tester,
    ) async {
      await h.open(tester, 'settlement');
      expect(find.byType(InventoryScreen), findsOneWidget);
      expect(find.text('Inventur & Abrechnung'), findsOneWidget);
      expect(find.text('Bier'), findsOneWidget);
      expect(find.text('Alkoholfrei'), findsOneWidget);
      expect(find.byKey(const Key('qty-row-d2')), findsOneWidget);
      expect(find.text('Entwurf fortgesetzt'), findsNothing);
    });

    testWidgets('Prüfen needs a count for every drink; 0 counts', (
      tester,
    ) async {
      await h.open(tester, 'settlement');
      expect(enabled(tester, reviewButton()), isFalse);
      await h.enter(tester, 'd1', crates: '2');
      await h.enter(tester, 'd2', units: '5');
      expect(enabled(tester, reviewButton()), isFalse);
      // Selecting a row is not a count.
      await tester.tap(find.byKey(const Key('qty-row-d3')));
      await tester.pump();
      expect(enabled(tester, reviewButton()), isFalse);
      await h.typeDigits(tester, '0');
      expect(enabled(tester, reviewButton()), isTrue);
    });

    testWidgets('every change saves the draft', (tester) async {
      await h.open(tester, 'settlement');
      expect(draft('settlement'), isNull);
      await h.enter(tester, 'd1', crates: '2');
      await tester.pump();
      expect(draft('settlement'), {
        'crates': {'d1': 2},
        'units': <String, dynamic>{},
      });
      await h.enter(tester, 'd3', crates: '0');
      await tester.pump();
      expect((draft('settlement')!['crates'] as Map)['d3'], 0);
      expect(draft('opening'), isNull);
    });

    testWidgets('a saved draft is restored with a note', (tester) async {
      h.store.values['count_draft_settlement'] = jsonEncode({
        'crates': {'d1': 2},
        'units': {'d1': 3, 'd2': 0},
      });
      await h.open(tester, 'settlement');
      expect(find.text('Entwurf fortgesetzt'), findsOneWidget);
      expect(find.text('= 43'), findsOneWidget);
      expect(enabled(tester, reviewButton()), isFalse);
      await h.enter(tester, 'd3', units: '4');
      expect(enabled(tester, reviewButton()), isTrue);
    });

    testWidgets('Verwerfen clears the draft after confirmation', (
      tester,
    ) async {
      await h.open(tester, 'settlement');
      await h.enter(tester, 'd1', crates: '2');
      await tester.pump();
      await tester.tap(find.byKey(const Key('count-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('count-discard-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('= 40'), findsOneWidget);
      expect(draft('settlement'), isNotNull);

      await tester.tap(find.byKey(const Key('count-discard')));
      await tester.pumpAndSettle();
      expect(find.text('Entwurf verwerfen?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('count-discard-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('= 40'), findsNothing);
      expect(draft('settlement'), isNull);
      expect(find.byType(InventoryScreen), findsOneWidget);
    });

    testWidgets('draft survives leaving and re-entering the flow', (
      tester,
    ) async {
      await h.open(tester, 'settlement');
      await h.enter(tester, 'd1', crates: '2', units: '3');
      await h.enter(tester, 'd2', units: '0');
      // Idle logout back to the name list.
      await tester.pump(countFlowIdle);
      await tester.pumpAndSettle();
      expect(find.byType(InventoryScreen), findsNothing);
      expect(find.byKey(const Key('admin-gear')), findsOneWidget);

      await h.login(tester);
      await tester.tap(find.byKey(const Key('admin-tile-settlement')));
      await tester.pumpAndSettle();
      expect(find.text('Entwurf fortgesetzt'), findsOneWidget);
      expect(find.text('= 43'), findsOneWidget);
      await h.enter(tester, 'd3', crates: '1');
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      expect(h.countsOf(h.requestsTo('settlement/review').single), {
        'd1': 43,
        'd2': 0,
        'd3': 12,
      });
    });

    testWidgets('Prüfen sends the counts in units and opens the review', (
      tester,
    ) async {
      await h.open(tester, 'settlement');
      await h.enterAll(tester);
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      expect(h.countsOf(h.requestsTo('settlement/review').single), {
        'd1': 43,
        'd2': 30,
        'd3': 12,
      });
      expect(find.byType(SettlementReviewScreen), findsOneWidget);
    });

    testWidgets('an ended session leaves to the PIN prompt', (tester) async {
      h.onStock = (_) async =>
          jsonResponse({'detail': 'admin_session_required'}, 401);
      await h.open(tester, 'settlement');
      expect(find.byType(InventoryScreen), findsNothing);
      expect(find.byKey(const Key('admin-pin-login')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('opening count', () {
    testWidgets('not allowed after the first settlement', (tester) async {
      h.onStock = (_) async => jsonResponse(stockJson(openingAllowed: false));
      await h.open(tester, 'opening');
      expect(h.sync.flushCalls, 0);
      expect(
        find.text('Anfangsbestand nur vor der ersten Abrechnung möglich'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qty-row-d1')), findsNothing);
      expect(saveButton(), findsNothing);
    });

    testWidgets('Speichern records the counts and returns home', (
      tester,
    ) async {
      await h.open(tester, 'opening');
      expect(find.text('Anfangsbestand'), findsOneWidget);
      expect(reviewButton(), findsNothing);
      expect(enabled(tester, saveButton()), isFalse);
      await h.enterAll(tester);
      await tester.pump();
      expect(draft('opening'), isNotNull);
      expect(draft('settlement'), isNull);
      await tester.tap(saveButton());
      await tester.pumpAndSettle();
      expect(h.countsOf(h.requestsTo('admin/opening-count').single), {
        'd1': 43,
        'd2': 30,
        'd3': 12,
      });
      expect(draft('opening'), isNull);
      expect(find.byType(InventoryScreen), findsNothing);
      expect(find.byType(AdminHome), findsOneWidget);
      expect(find.text('Anfangsbestand gespeichert'), findsOneWidget);
    });

    testWidgets('a refused save keeps the counts and says why', (tester) async {
      h.onOpening = (_) async =>
          jsonResponse({'detail': 'already_settled'}, 409);
      await h.open(tester, 'opening');
      await h.enterAll(tester);
      await tester.tap(saveButton());
      await tester.pumpAndSettle();
      expect(
        find.text('Anfangsbestand nur vor der ersten Abrechnung möglich'),
        findsOneWidget,
      );
      expect(find.byType(InventoryScreen), findsOneWidget);
      expect(draft('opening'), isNotNull);
    });
  });
}
