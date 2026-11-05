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
