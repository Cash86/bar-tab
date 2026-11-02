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
}
