import 'dart:async';
import 'dart:convert';

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

  Future<void> openReview(WidgetTester tester) async {
    await h.open(tester, 'settlement');
    await h.enterAll(tester);
    await tester.tap(find.byKey(const Key('count-review')));
    await tester.pumpAndSettle();
    expect(find.byType(SettlementReviewScreen), findsOneWidget);
  }

  Finder inRow(String key, String text) =>
      find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settlement-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settlement-close-confirm')));
    await tester.pumpAndSettle();
  }

  void closeAnswers(String mailStatus) {
    h.onClose = (_) async => jsonResponse({
      'period_id': 'p1',
      'closed_at': '2026-11-09T21:00:00Z',
      'mail_status': mailStatus,
    }, 201);
  }

  testWidgets('shows drinks, group subtotals and totals', (tester) async {
    await openReview(tester);
    for (final header in ['erwartet', 'gezählt', 'Schwund', 'Wert']) {
      expect(find.text(header), findsOneWidget);
    }
    expect(inRow('review-drink-d1', 'Pils'), findsOneWidget);
    expect(inRow('review-drink-d1', '50'), findsOneWidget);
    expect(inRow('review-drink-d1', '43'), findsOneWidget);
    expect(inRow('review-drink-d1', '7'), findsOneWidget);
    expect(inRow('review-drink-d1', '8,40 €'), findsOneWidget);
    expect(inRow('review-drink-d2', 'kein Preis'), findsOneWidget);
    expect(inRow('review-drink-d1', 'kein Preis'), findsNothing);
    expect(inRow('review-drink-d3', '-2'), findsOneWidget);
    expect(inRow('review-drink-d3', '-1,60 €'), findsOneWidget);
    expect(inRow('review-group-g1', 'Bier'), findsOneWidget);
    expect(inRow('review-group-g1', '73'), findsOneWidget);
    expect(inRow('review-group-g1', 'kein Preis'), findsOneWidget);
    expect(inRow('review-group-g2', 'Alkoholfrei'), findsOneWidget);
    expect(inRow('review-total-persons', 'Mitglieder'), findsOneWidget);
    expect(inRow('review-total-persons', '123,45 €'), findsOneWidget);
    expect(inRow('review-total-hidden', 'versteckte Konten'), findsOneWidget);
    expect(inRow('review-total-hidden', '5,00 €'), findsOneWidget);
    expect(inRow('review-total-grand', 'Gesamt'), findsOneWidget);
    expect(inRow('review-total-grand', '128,45 €'), findsOneWidget);
    expect(inRow('review-total-shrinkage', 'Schwund gesamt'), findsOneWidget);
    expect(inRow('review-total-shrinkage', '6,80 €'), findsOneWidget);
    expect(
      inRow('review-total-shrinkage', 'bewertet mit Aktive'),
      findsOneWidget,
    );
  });

  testWidgets('Zurück keeps the counts', (tester) async {
    await openReview(tester);
    await tester.tap(find.byKey(const Key('review-back')));
    await tester.pumpAndSettle();
    expect(find.byType(InventoryScreen), findsOneWidget);
    expect(find.text('= 43'), findsOneWidget);
    expect(h.requestsTo('settlement/close'), isEmpty);
  });

  testWidgets('cancelling the confirmation closes nothing', (tester) async {
    await openReview(tester);
    await tester.tap(find.byKey(const Key('settlement-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settlement-close-cancel')));
    await tester.pumpAndSettle();
    expect(h.requestsTo('settlement/close'), isEmpty);
    expect(find.byType(SettlementReviewScreen), findsOneWidget);
  });

  testWidgets('closing sends token and counts, clears the draft, mail sent', (
    tester,
  ) async {
    await openReview(tester);
    expect(h.store.values['count_draft_settlement'], isNotNull);
    await close(tester);
    final body =
        jsonDecode(h.requestsTo('settlement/close').single.body)
            as Map<String, dynamic>;
    expect(body['token'], 'rev-1');
    expect(h.countsOf(h.requestsTo('settlement/close').single), {
      'd1': 43,
      'd2': 30,
      'd3': 12,
    });
    expect(h.store.values['count_draft_settlement'], isNull);
    expect(find.text('Abgeschlossen, PDF verschickt'), findsOneWidget);
    expect(find.byType(SettlementReviewScreen), findsNothing);
    expect(find.byType(InventoryScreen), findsNothing);
    expect(find.byType(AdminHome), findsOneWidget);
  });

  testWidgets('a failed mail says how to re-send', (tester) async {
    closeAnswers('failed');
    await openReview(tester);
    await close(tester);
    expect(
      find.text(
        'Abgeschlossen – Mail fehlgeschlagen, in Einstellungen erneut senden',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a skipped mail says why', (tester) async {
    closeAnswers('skipped');
    await openReview(tester);
    await close(tester);
    expect(
      find.text(
        'Abgeschlossen – keine Mail (keine Empfänger oder kein Mailserver)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a replayed close (200) counts as success', (tester) async {
    h.onClose = (_) async => jsonResponse({
      'period_id': 'p1',
      'closed_at': '2026-11-09T21:00:00Z',
      'mail_status': 'sent',
    });
    await openReview(tester);
    await close(tester);
    expect(find.text('Abgeschlossen, PDF verschickt'), findsOneWidget);
    expect(find.byType(AdminHome), findsOneWidget);
  });

  testWidgets('a stale review reloads and asks to check again', (tester) async {
    h.onClose = (_) async => jsonResponse({'detail': 'stale_review'}, 409);
    await openReview(tester);
    h.onReview = (_) async =>
        jsonResponse(reviewJson(token: 'rev-2', pilsCounted: 40));
    await close(tester);
    expect(
      find.text('Daten haben sich geändert – bitte erneut prüfen'),
      findsOneWidget,
    );
    expect(h.requestsTo('settlement/review'), hasLength(2));
    expect(find.byType(SettlementReviewScreen), findsOneWidget);
    expect(inRow('review-drink-d1', '10'), findsOneWidget);
    expect(h.store.values['count_draft_settlement'], isNotNull);

    closeAnswers('sent');
    await close(tester);
    final body =
        jsonDecode(h.requestsTo('settlement/close').last.body)
            as Map<String, dynamic>;
    expect(body['token'], 'rev-2');
  });

  for (final detail in ['missing_count', 'unknown_reference']) {
    testWidgets('a changed count list after a stale review ($detail) goes '
        'back to the count with the new list', (tester) async {
      h.onClose = (_) async => jsonResponse({'detail': 'stale_review'}, 409);
      await openReview(tester);
      // Fass is gone from the list, Radler is new.
      final changed = stockJson();
      final drinks = (changed['drinks'] as List).cast<Map<String, dynamic>>();
      changed['drinks'] = [
        drinks[0],
        drinks[2],
        {
          'drink_id': 'd4',
          'name': 'Radler',
          'group_id': 'g1',
          'group_name': 'Bier',
          'crate_size': 20,
          'expected': 5,
        },
      ];
      h.onStock = (_) async => jsonResponse(changed);
      h.onReview = (_) async => jsonResponse({'detail': detail}, 422);
      await close(tester);

      expect(find.byType(SettlementReviewScreen), findsNothing);
      expect(find.byType(InventoryScreen), findsOneWidget);
      expect(
        find.text('Getränkeliste hat sich geändert – bitte Zählung prüfen'),
        findsOneWidget,
      );
      expect(h.requestsTo('admin/stock'), hasLength(2));
      expect(find.byKey(const Key('qty-row-d4')), findsOneWidget);
      expect(find.byKey(const Key('qty-row-d2')), findsNothing);
      // Counts of drinks still listed are kept; the gone one is dropped.
      expect(find.text('= 43'), findsOneWidget);
      final draft =
          jsonDecode(h.store.values['count_draft_settlement']!)
              as Map<String, dynamic>;
      expect((draft['units'] as Map).containsKey('d2'), isFalse);
      expect((draft['units'] as Map)['d1'], 3);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('count-review')))
            .enabled,
        isFalse,
      );

      await h.enter(tester, 'd4', units: '5');
      h.onReview = (_) async => jsonResponse(reviewJson(token: 'rev-3'));
      await tester.tap(find.byKey(const Key('count-review')));
      await tester.pumpAndSettle();
      expect(h.countsOf(h.requestsTo('settlement/review').last), {
        'd1': 43,
        'd3': 12,
        'd4': 5,
      });
    });
  }

  testWidgets('a lost close answer keeps the review; a retry replays', (
    tester,
  ) async {
    h.onClose = (_) async => throw http.ClientException('down');
    await openReview(tester);
    await close(tester);
    expect(
      find.text('Status unklar – bitte erneut abschließen'),
      findsOneWidget,
    );
    expect(find.text('Server nicht erreichbar'), findsNothing);
    expect(find.byType(SettlementReviewScreen), findsOneWidget);
    expect(h.requestsTo('settlement/review'), hasLength(1));
    expect(h.store.values['count_draft_settlement'], isNotNull);

    closeAnswers('sent');
    await tester.pump(const Duration(seconds: 5));
    await close(tester);
    final tokens = [
      for (final r in h.requestsTo('settlement/close'))
        (jsonDecode(r.body) as Map<String, dynamic>)['token'],
    ];
    expect(tokens, ['rev-1', 'rev-1']);
    expect(find.text('Abgeschlossen, PDF verschickt'), findsOneWidget);
    expect(find.byType(AdminHome), findsOneWidget);
  });

  testWidgets('the review cannot be left while the close runs', (tester) async {
    final answer = Completer<http.Response>();
    h.onClose = (_) => answer.future;
    await openReview(tester);
    await close(tester);
    expect(h.requestsTo('settlement/close'), hasLength(1));
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('review-back')))
          .enabled,
      isFalse,
    );
    // System back and the app bar back are blocked.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SettlementReviewScreen), findsOneWidget);
    final back = find.byType(BackButton);
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back);
      await tester.pumpAndSettle();
    }
    expect(find.byType(SettlementReviewScreen), findsOneWidget);

    answer.complete(
      jsonResponse({
        'period_id': 'p1',
        'closed_at': '2026-11-09T21:00:00Z',
        'mail_status': 'sent',
      }, 201),
    );
    await tester.pumpAndSettle();
    expect(h.store.values['count_draft_settlement'], isNull);
    expect(find.text('Abgeschlossen, PDF verschickt'), findsOneWidget);
    expect(find.byType(AdminHome), findsOneWidget);
  });

  testWidgets('a failing review load says so', (tester) async {
    h.onReview = (_) async => throw http.ClientException('down');
    await openReview(tester);
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    expect(find.byKey(const Key('settlement-close')), findsNothing);
  });
}
