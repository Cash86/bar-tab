import 'package:bar_tab/presentation/admin/count_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fakes.dart';

void main() {
  late FakeConfigStore config;
  late CountDraftStore store;
  const lines = {
    'crates': {'d1': 2},
    'units': {'d1': 0, 'd4': 5},
  };

  setUp(() {
    config = FakeConfigStore();
    store = CountDraftStore(config);
  });

  test('loads null when nothing is saved', () async {
    expect(await store.load(CountMode.settlement), isNull);
  });

  test('saves and loads a draft per mode', () async {
    await store.save(CountMode.settlement, lines);
    expect(await store.load(CountMode.settlement), lines);
    expect(await store.load(CountMode.opening), isNull);
    expect(config.values.keys, ['count_draft_settlement']);
  });

  test('clear removes only the given mode', () async {
    await store.save(CountMode.settlement, lines);
    await store.save(CountMode.opening, lines);
    await store.clear(CountMode.settlement);
    expect(await store.load(CountMode.settlement), isNull);
    expect(await store.load(CountMode.opening), lines);
    expect(config.values.keys, ['count_draft_opening']);
  });

  test('corrupt JSON loads as null', () async {
    config.values['count_draft_opening'] = '{not json';
    expect(await store.load(CountMode.opening), isNull);
    config.values['count_draft_opening'] = '[1, 2]';
    expect(await store.load(CountMode.opening), isNull);
  });
}
