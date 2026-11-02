import 'booking.dart';

/// Server tab plus local bookings the server tab does not yet include.
/// Callers pass only the selected person's bookings.
int runningTotalCents({
  required int serverTabCents,
  required Iterable<Booking> localBookings,
}) {
  var total = serverTabCents;
  for (final b in localBookings) {
    final counts =
        (b.status == BookingStatus.queued ||
            b.status == BookingStatus.accepted) &&
        !b.includedInTabs;
    if (counts) total += b.quantity * b.unitPriceCents;
  }
  return total;
}
