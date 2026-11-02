import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/running_total.dart';
import 'package:flutter_test/flutter_test.dart';

Booking booking(
  BookingStatus status, {
  bool included = false,
  int quantity = 2,
  int price = 100,
}) => Booking(
  id: 'b-${status.name}-$included',
  personId: 'p1',
  drinkId: 'd1',
  quantity: quantity,
  unitPriceCents: price,
  bookedAt: DateTime.utc(2026, 11, 2),
  status: status,
  includedInTabs: included,
);

void main() {
  final cases = <(String, List<Booking>, int)>[
    ('no bookings', [], 1000),
    ('queued counts', [booking(BookingStatus.queued)], 1200),
    ('accepted not included counts', [booking(BookingStatus.accepted)], 1200),
    (
      'accepted included excluded',
      [booking(BookingStatus.accepted, included: true)],
      1000,
    ),
    ('rejected excluded', [booking(BookingStatus.rejected)], 1000),
    ('conflict excluded', [booking(BookingStatus.conflict)], 1000),
    (
      'mixed',
      [
        booking(BookingStatus.queued, quantity: 3, price: 50),
        booking(BookingStatus.accepted, quantity: 1, price: 70),
        booking(BookingStatus.rejected),
        booking(BookingStatus.accepted, included: true),
      ],
      1000 + 150 + 70,
    ),
  ];

  for (final (name, bookings, expected) in cases) {
    test(name, () {
      expect(
        runningTotalCents(serverTabCents: 1000, localBookings: bookings),
        expected,
      );
    });
  }
}
