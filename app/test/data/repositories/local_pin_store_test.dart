import 'dart:math';

import 'package:bar_tab/data/repositories/local_pin_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fakes.dart';

void main() {
  late FakeConfigStore config;
  late LocalPinStore store;

  setUp(() {
    config = FakeConfigStore();
    store = LocalPinStore(config, iterations: 2, random: Random(1));
  });

  test('hasPin is false on an empty store', () async {
    expect(await store.hasPin(), isFalse);
    expect(await store.verify('1234'), isFalse);
  });

  test('remember then verify accepts the pin and rejects others', () async {
    await store.remember('1234');
    expect(await store.hasPin(), isTrue);
    expect(await store.verify('1234'), isTrue);
    expect(await store.verify('1235'), isFalse);
    expect(await store.verify(''), isFalse);
  });

  test('the stored value has the v1 format and never holds the pin', () async {
    await store.remember('4711');
    final value = config.values['admin_pin_local']!;
    final parts = value.split(r'$');
    expect(parts, hasLength(4));
    expect(parts[0], 'v1');
    expect(parts[1], '2');
    expect(value, isNot(contains('4711')));
  });

  test('remembering again replaces the pin and uses a fresh salt', () async {
    await store.remember('1234');
    final first = config.values['admin_pin_local'];
    await store.remember('9999');
    expect(config.values['admin_pin_local'], isNot(first));
    expect(await store.verify('1234'), isFalse);
    expect(await store.verify('9999'), isTrue);
  });

  test('a garbled stored value verifies false and never throws', () async {
    for (final bad in [
      'junk',
      r'v2$2$AA==$AA==',
      r'v1$x$AA==$AA==',
      r'v1$2$!!!$!!!',
      r'v1$0$AA==$AA==',
      r'v1$2$AA==',
    ]) {
      config.values['admin_pin_local'] = bad;
      expect(await store.verify('1234'), isFalse, reason: bad);
    }
  });
}
