import 'package:intl/intl.dart';

final NumberFormat _euro = NumberFormat.currency(locale: 'de_DE', symbol: '€');

/// Formats integer cents as a German euro amount, e.g. `1,15 €`.
///
/// intl emits a non-breaking space (U+00A0) between amount and `€`; tests
/// assert on that exact string.
String formatCents(int cents) => _euro.format(cents / 100);

final RegExp _euroInput = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$');

/// Parses a typed euro amount (`1,40`, `1.4`, `2`) into integer cents; null
/// for anything else (empty, negative, more than two decimals).
int? parseEuroCents(String input) {
  final m = _euroInput.firstMatch(input.trim());
  if (m == null) return null;
  final fraction = (m.group(2) ?? '').padRight(2, '0');
  return int.parse(m.group(1)!) * 100 + int.parse(fraction);
}

/// Integer cents as an editable amount without currency sign, e.g. `1,40`.
String formatCentsPlain(int cents) =>
    '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

// Digits only, so no locale data has to be loaded.
final DateFormat _bookingTime = DateFormat('dd.MM. HH:mm');

/// Formats a booking time in local time, e.g. `05.11. 21:07`.
String formatBookingTime(DateTime time) => _bookingTime.format(time.toLocal());
