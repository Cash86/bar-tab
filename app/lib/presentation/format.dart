import 'package:intl/intl.dart';

final NumberFormat _euro = NumberFormat.currency(locale: 'de_DE', symbol: '€');

/// Formats integer cents as a German euro amount, e.g. `1,15 €`.
///
/// intl emits a non-breaking space (U+00A0) between amount and `€`; tests
/// assert on that exact string.
String formatCents(int cents) => _euro.format(cents / 100);
