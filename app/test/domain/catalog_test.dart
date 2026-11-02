import 'package:bar_tab/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Person person(
  String id,
  String name, {
  String tier = 't1',
  bool hidden = false,
  bool collective = false,
  bool active = true,
}) => Person(
  id: id,
  name: name,
  priceTierId: tier,
  isHidden: hidden,
  isCollective: collective,
  isActive: active,
);

Drink drink(
  String id,
  String name, {
  String group = 'g1',
  int sortOrder = 0,
  bool hidden = false,
  bool active = true,
  Map<String, int> prices = const {'t1': 100},
}) => Drink(
  id: id,
  name: name,
  groupId: group,
  crateSize: 24,
  sortOrder: sortOrder,
  isHidden: hidden,
  isActive: active,
  prices: prices,
);

Catalog catalog({
  List<PriceTier>? tiers,
  List<Person> persons = const [],
  List<DrinkGroup>? groups,
  List<Drink> drinks = const [],
}) => Catalog(
  tiers:
      tiers ??
      const [
        PriceTier(id: 't2', name: 'Second', sortOrder: 2),
        PriceTier(id: 't1', name: 'First', sortOrder: 1),
      ],
  persons: persons,
  groups:
      groups ??
      const [
        DrinkGroup(id: 'g2', name: 'Soft', sortOrder: 2, color: 0xFF112233),
        DrinkGroup(id: 'g1', name: 'Beer', sortOrder: 1, color: 0xFF445566),
      ],
  drinks: drinks,
  etag: 'e1',
);

void main() {
  group('personsByTier', () {
    test('groups visible persons by tier, ordered, omitting empty tiers', () {
      final c = catalog(
        tiers: const [
          PriceTier(id: 't2', name: 'Second', sortOrder: 2),
          PriceTier(id: 't1', name: 'First', sortOrder: 1),
          PriceTier(id: 't3', name: 'Empty', sortOrder: 3),
        ],
        persons: [
          person('p5', 'Zed', tier: 't2'),
          person('p2', 'Ann', tier: 't1'),
          person('p1', 'Ann', tier: 't1'),
          person('p3', 'Bob', tier: 't1', hidden: true),
          person('p4', 'Cy', tier: 't1', active: false),
          person('p6', 'Pot', tier: 't1', collective: true),
          person('p7', 'Only hidden', tier: 't3', hidden: true),
        ],
      );
      final result = c.personsByTier();
      expect(result.map((e) => e.$1.id), ['t1', 't2']);
      expect(result[0].$2.map((p) => p.id), ['p1', 'p2']);
      expect(result[1].$2.map((p) => p.id), ['p5']);
    });
  });

  test('collectiveAccounts: active, visible, collective, by name', () {
    final c = catalog(
      persons: [
        person('p1', 'Zeta', collective: true),
        person('p2', 'Alpha', collective: true),
        person('p3', 'Hidden', collective: true, hidden: true),
        person('p4', 'Off', collective: true, active: false),
        person('p5', 'Normal'),
      ],
    );
    expect(c.collectiveAccounts().map((p) => p.id), ['p2', 'p1']);
  });

  group('drinksFor', () {
    test('filters and orders drinks, omitting empty groups', () {
      final c = catalog(
        drinks: [
          drink('d1', 'Stout', sortOrder: 2),
          drink('d2', 'Ale', sortOrder: 2),
          drink('d3', 'Lager', sortOrder: 1),
          drink('d4', 'Hid', hidden: true),
          drink('d5', 'Off', active: false),
          drink('d6', 'NoPrice', prices: const {'t2': 100}),
          drink('d7', 'Cola', group: 'g2', prices: const {'t2': 100}),
        ],
      );
      final result = c.drinksFor(person('p1', 'Ann'));
      expect(result.map((e) => e.$1.id), ['g1']);
      expect(result[0].$2.map((d) => d.id), ['d3', 'd2', 'd1']);
    });

    test('uses the person tier to include other groups', () {
      final c = catalog(
        drinks: [
          drink('d1', 'Lager'),
          drink('d7', 'Cola', group: 'g2', prices: const {'t2': 100}),
        ],
      );
      final result = c.drinksFor(person('p2', 'Bo', tier: 't2'));
      expect(result.map((e) => e.$1.id), ['g2']);
    });
  });

  test('priceFor returns tier price or null', () {
    final c = catalog();
    final d = drink('d1', 'Lager', prices: const {'t1': 250});
    expect(c.priceFor(d, person('p1', 'A', tier: 't1')), 250);
    expect(c.priceFor(d, person('p2', 'B', tier: 't2')), isNull);
  });

  test('names sort German-friendly: case-insensitive, umlauts as base', () {
    final c = catalog(
      persons: [
        person('p1', 'Zoe'),
        person('p2', 'Ömer'),
        person('p3', 'de Vries'),
        person('p4', 'Anna'),
        person('p5', 'Uwe'),
        person('p6', 'Ünal'),
        person('p7', 'Ärztin'),
        person('p9', 'Ömer'),
      ],
    );
    expect(c.personsByTier().single.$2.map((p) => p.id), [
      'p4', // Anna
      'p7', // Ärztin (a-r)
      'p3', // de Vries
      'p2', // Ömer (o), id tie-break
      'p9',
      'p6', // Ünal (u-n) before Uwe (u-w)
      'p5',
      'p1',
    ]);
  });

  test('drink name tie-break is folded too', () {
    final c = catalog(
      drinks: [drink('d1', 'Zitrone'), drink('d2', 'Öl'), drink('d3', 'apfel')],
    );
    final result = c.drinksFor(person('p1', 'Ann'));
    expect(result[0].$2.map((d) => d.id), ['d3', 'd2', 'd1']);
  });
}
