import 'package:bar_tab/domain/order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OrderDraft tapN(OrderDraft d, String id, int price, int n) {
    for (var i = 0; i < n; i++) {
      d = d.tap(id, price).draft;
    }
    return d;
  }

  test('empty draft', () {
    final d = const OrderDraft.empty('p1');
    expect(d.personId, 'p1');
    expect(d.isEmpty, isTrue);
    expect(d.totalCents, 0);
  });

  test('quantity sheet opens exactly when quantity reaches 3', () {
    var d = const OrderDraft.empty('p1');
    final expected = [(1, false), (2, false), (3, true), (4, false)];
    for (final (qty, sheet) in expected) {
      final r = d.tap('d1', 100);
      d = r.draft;
      expect(d.lines.single.quantity, qty);
      expect(r.openQuantitySheet, sheet, reason: 'qty $qty');
    }
  });

  test('lines keep first-tap order', () {
    var d = const OrderDraft.empty('p1');
    d = d.tap('b', 100).draft;
    d = d.tap('a', 200).draft;
    d = d.tap('b', 100).draft;
    expect(d.lines.map((l) => l.drinkId), ['b', 'a']);
  });

  test('price is fixed at first tap', () {
    var d = const OrderDraft.empty('p1');
    d = d.tap('d1', 100).draft;
    d = d.tap('d1', 999).draft;
    expect(d.lines.single.unitPriceCents, 100);
    expect(d.totalCents, 200);
  });

  test('setQuantity 0 removes the line', () {
    final d = tapN(
      const OrderDraft.empty('p1'),
      'd1',
      100,
      2,
    ).setQuantity('d1', 0);
    expect(d.isEmpty, isTrue);
  });

  test('setQuantity updates quantity and keeps price', () {
    final d = tapN(
      const OrderDraft.empty('p1'),
      'd1',
      100,
      1,
    ).setQuantity('d1', 999);
    expect(d.lines.single.quantity, 999);
    expect(d.lines.single.unitPriceCents, 100);
  });

  test('setQuantity out of range throws', () {
    final d = tapN(const OrderDraft.empty('p1'), 'd1', 100, 1);
    expect(() => d.setQuantity('d1', 1000), throwsArgumentError);
    expect(() => d.setQuantity('d1', -1), throwsArgumentError);
  });

  test('setQuantity on unknown drink throws', () {
    expect(
      () => const OrderDraft.empty('p1').setQuantity('nope', 2),
      throwsArgumentError,
    );
  });

  test('totalCents sums quantity times price', () {
    var d = tapN(const OrderDraft.empty('p1'), 'a', 150, 3);
    d = tapN(d, 'b', 220, 2);
    expect(d.totalCents, 3 * 150 + 2 * 220);
  });

  test('tap caps at 999 and does not open the sheet', () {
    var d = tapN(const OrderDraft.empty('p1'), 'd1', 100, 1);
    d = d.setQuantity('d1', 999);
    final r = d.tap('d1', 100);
    expect(r.draft.lines.single.quantity, 999);
    expect(r.openQuantitySheet, isFalse);
  });
}
