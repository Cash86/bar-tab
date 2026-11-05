import 'package:intl/intl.dart';

final NumberFormat _euro = NumberFormat.currency(locale: 'de_DE', symbol: '€');

/// Formats integer cents as a German euro amount, e.g. `1,15 €`.
///
/// intl emits a non-breaking space (U+00A0) between amount and `€`; tests
/// assert on that exact string.
String formatCents(int cents) => _euro.format(cents / 100);

// Digits only, so no locale data has to be loaded.
final DateFormat _bookingTime = DateFormat('dd.MM. HH:mm');

/// Formats a booking time in local time, e.g. `05.11. 21:07`.
String formatBookingTime(DateTime time) => _bookingTime.format(time.toLocal());
