import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/quick_bar.dart';
import 'package:bar_tab/domain/rankings.dart';
import 'package:flutter_test/flutter_test.dart';

Drink drink(
  String id, {
  int sortOrder = 0,
  bool hidden = false,
  bool keg = false,
  bool active = true,
  Map<String, int> prices = const {'t1': 100},
}) => Drink(
  id: id,
  name: id,
  groupId: 'g1',
  crateSize: 24,
  sortOrder: sortOrder,
  isHidden: hidden,
  isKeg: keg,
  isActive: active,
  prices: prices,
);

const ann = Person(
  id: 'p1',
  name: 'Ann',
  priceTierId: 't1',
  isHidden: false,
  isCollective: false,
  isActive: true,
);

Catalog catalog() => Catalog(
  tiers: const [PriceTier(id: 't1', name: 'First', sortOrder: 1)],
  persons: const [ann],
  groups: const [
    DrinkGroup(id: 'g1', name: 'Beer', sortOrder: 1, color: 0xFF445566),
  ],
  drinks: [
    drink('Helles', sortOrder: 1),
    drink('Cola-Mix', sortOrder: 2),
    drink('Wasser', sortOrder: 3),
    drink('Weizen', sortOrder: 4),
    drink('Pils', sortOrder: 5),
    drink('Hidden', sortOrder: 6, hidden: true),
    drink('Fass', sortOrder: 9, keg: true),
    drink('Inactive', sortOrder: 7, active: false),
    drink('OtherTier', sortOrder: 8, prices: const {'t2': 100}),
  ],
  etag: 'e1',
);

List<String> pick(DrinkRankings? r, {int size = kQuickBarSize}) =>
    quickBarDrinks(catalog(), ann, r, size: size).map((d) => d.id).toList();

DrinkRankings rankings(
  Map<String, int> overall, [
  Map<String, int> own = const {},
]) => DrinkRankings(overall: overall, persons: {if (own.isNotEmpty) 'p1': own});

const overall = {
  'Helles': 89,
  'Cola-Mix': 50,
  'Wasser': 48,
  'Weizen': 34,
  'Pils': 10,
};

void main() {
  test('a new person gets the overall top 4', () {
    expect(pick(rankings(overall)), ['Helles', 'Cola-Mix', 'Wasser', 'Weizen']);
  });

  test('own drinks come first, then the overall list without them', () {
    expect(pick(rankings(overall, {'Pils': 1})), [
      'Pils',
      'Helles',
      'Cola-Mix',
      'Wasser',
    ]);
  });

  test('own drinks are ranked by their own count', () {
    expect(pick(rankings(overall, {'Wasser': 1, 'Weizen': 5})), [
      'Weizen',
      'Wasser',
      'Helles',
      'Cola-Mix',
    ]);
  });

  test('ties follow the grid order', () {
    expect(pick(rankings({'Weizen': 3, 'Helles': 3})), ['Helles', 'Weizen']);
    expect(pick(rankings({}, {'Weizen': 3, 'Helles': 3})), [
      'Helles',
      'Weizen',
    ]);
  });

  test('drinks the person cannot book are skipped', () {
    final r = rankings({
      'Hidden': 100,
      'Fass': 100,
      'Inactive': 99,
      'OtherTier': 98,
      'Unknown': 97,
      'Helles': 5,
      'Cola-Mix': 4,
    });
    expect(pick(r), ['Helles', 'Cola-Mix']);
  });

  test('an own drink is not repeated from the overall list', () {
    expect(pick(rankings(overall, {'Helles': 1})), [
      'Helles',
      'Cola-Mix',
      'Wasser',
      'Weizen',
    ]);
  });

  test('the overall list is ranked by count, not grid order', () {
    expect(pick(rankings({'Pils': 9, 'Helles': 2})), ['Pils', 'Helles']);
  });

  test('the size limits the list', () {
    expect(pick(rankings(overall), size: 2), ['Helles', 'Cola-Mix']);
  });

  test('fewer ranked drinks give a shorter list', () {
    expect(pick(rankings({'Helles': 1})), ['Helles']);
  });

  test('no rankings give an empty list', () {
    expect(pick(null), isEmpty);
    expect(pick(rankings({})), isEmpty);
  });
}
