import 'package:bar_tab/presentation/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCents', () {
    test('formats cents with comma and euro sign', () {
      expect(formatCents(115), '1,15 €');
    });

    test('formats zero', () {
      expect(formatCents(0), '0,00 €');
    });

    test('uses dot as thousands separator', () {
      expect(formatCents(123456), '1.234,56 €');
    });
  });

  group('parseEuroCents', () {
    test('accepts comma, dot and whole euros', () {
      expect(parseEuroCents('1,40'), 140);
      expect(parseEuroCents('1.4'), 140);
      expect(parseEuroCents('2'), 200);
      expect(parseEuroCents(' 0,05 '), 5);
    });

    test('rejects sub-cent, negative and empty input', () {
      expect(parseEuroCents('1,405'), isNull);
      expect(parseEuroCents('-1'), isNull);
      expect(parseEuroCents(''), isNull);
      expect(parseEuroCents('1,'), isNull);
      expect(parseEuroCents('abc'), isNull);
    });
  });

  group('formatCentsPlain', () {
    test('writes cents as an editable amount', () {
      expect(formatCentsPlain(140), '1,40');
      expect(formatCentsPlain(5), '0,05');
      expect(formatCentsPlain(200), '2,00');
    });
  });

  group('formatBookingTime', () {
    test('shows day, month and time in local time', () {
      final local = DateTime(2026, 11, 5, 21, 7);
      expect(formatBookingTime(local.toUtc()), '05.11. 21:07');
    });

    test('pads single digits', () {
      expect(formatBookingTime(DateTime(2026, 1, 2, 3, 4)), '02.01. 03:04');
    });
  });
}
