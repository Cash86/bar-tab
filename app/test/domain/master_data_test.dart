import 'package:bar_tab/domain/master_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cleanName', () {
    test('trims', () => expect(cleanName('  Jörg  ', maxPersonName), 'Jörg'));

    test('empty or blank is null', () {
      expect(cleanName('', maxPersonName), isNull);
      expect(cleanName('   ', maxPersonName), isNull);
    });

    test('20 runes are fine, 21 are not (persons)', () {
      expect(cleanName('a' * 20, maxPersonName), 'a' * 20);
      expect(cleanName('a' * 21, maxPersonName), isNull);
    });

    test('an umlaut counts as one, so does an emoji', () {
      expect(cleanName('ä' * 20, maxPersonName), 'ä' * 20);
      expect(cleanName('😀' * 20, maxPersonName), '😀' * 20);
      expect(cleanName('😀' * 21, maxPersonName), isNull);
    });

    test('the limits are 20, 24, 16, 16', () {
      expect(
        [maxPersonName, maxDrinkName, maxGroupName, maxTierName],
        [20, 24, 16, 16],
      );
    });
  });

  group('nameTaken', () {
    const others = [(id: 'a', name: 'Jörg'), (id: 'b', name: 'Anna')];

    test('compares case-insensitively and trimmed', () {
      expect(nameTaken('  jÖrg ', others), isTrue);
      expect(nameTaken('Berta', others), isFalse);
    });

    test('ignores exceptId', () {
      expect(nameTaken('Jörg', others, exceptId: 'a'), isFalse);
      expect(nameTaken('Jörg', others, exceptId: 'b'), isTrue);
    });
  });

  test('unitsOf adds crates times crate size to single units', () {
    expect(unitsOf(crates: 2, units: 3, crateSize: 20), 43);
  });
}
