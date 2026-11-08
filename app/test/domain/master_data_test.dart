import 'dart:math' as math;

import 'package:bar_tab/domain/master_data.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(String hex) {
  double lin(int v) {
    final c = v / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final n = int.parse(hex.substring(1), radix: 16);
  return 0.2126 * lin((n >> 16) & 0xFF) +
      0.7152 * lin((n >> 8) & 0xFF) +
      0.0722 * lin(n & 0xFF);
}

double _contrast(String a, String b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('groupPalette', () {
    test('has 12 distinct valid #RRGGBB values', () {
      expect(groupPalette, hasLength(12));
      expect(groupPalette.toSet(), hasLength(12));
      for (final c in groupPalette) {
        expect(c, matches(RegExp(r'^#[0-9A-F]{6}$')));
      }
    });

    test('is readable (contrast >= 3.0) on cream, bottle and chalkboard', () {
      const backgrounds = {
        'cream': '#F3E7CF',
        'bottle': '#16302A',
        'chalkboard': '#232724',
      };
      // Guards the hard-coded bottle value against theme drift.
      expect(
        BarTabTheme.bottle.toARGB32() & 0xFFFFFF,
        int.parse(backgrounds['bottle']!.substring(1), radix: 16),
      );
      for (final c in groupPalette) {
        for (final MapEntry(:key, :value) in backgrounds.entries) {
          expect(
            _contrast(c, value),
            greaterThanOrEqualTo(3.0),
            reason: '$c on $key',
          );
        }
      }
    });
  });

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
