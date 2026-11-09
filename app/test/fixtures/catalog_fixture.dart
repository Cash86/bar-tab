/// Catalog response in the server's wire shape (invented values).
const catalogFixtureJson = <String, dynamic>{
  'price_tiers': [
    {'id': 't1', 'name': 'Members', 'sort_order': 1},
    {'id': 't2', 'name': 'Guests', 'sort_order': 2},
  ],
  'persons': [
    {
      'id': 'p1',
      'name': 'Alex Example',
      'price_tier_id': 't1',
      'is_hidden': false,
      'is_collective': false,
      'is_active': true,
    },
    {
      'id': 'p2',
      'name': 'Bar Team',
      'price_tier_id': 't2',
      'is_hidden': false,
      'is_collective': true,
      'is_active': true,
    },
  ],
  'groups': [
    {'id': 'g1', 'name': 'Beer', 'sort_order': 1, 'color': '#C8A02B'},
  ],
  'drinks': [
    {
      'id': 'd1',
      'name': 'Lager',
      'group_id': 'g1',
      'crate_size': 20,
      'sort_order': 1,
      'is_hidden': false,
      'is_active': true,
      'is_keg': false,
      'prices': {'t1': 150, 't2': 200},
    },
  ],
  'etag': 'abc123',
};
