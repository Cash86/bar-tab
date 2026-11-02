import 'package:bar_tab/domain/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FixedClock returns its time and can advance', () {
    final clock = FixedClock(DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(clock.now(), DateTime.utc(2026, 1, 2, 3, 4, 5));
    clock.advance(const Duration(minutes: 5));
    expect(clock.now(), DateTime.utc(2026, 1, 2, 3, 9, 5));
  });

  test('SystemClock returns UTC', () {
    expect(SystemClock().now().isUtc, isTrue);
  });
}
