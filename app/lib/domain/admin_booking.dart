import 'package:freezed_annotation/freezed_annotation.dart';

part 'admin_booking.freezed.dart';

/// A booking as the admin area sees it, including stornos.
@freezed
abstract class AdminBooking with _$AdminBooking {
  const AdminBooking._();

  const factory AdminBooking({
    required String id,
    required String personId,
    required String drinkId,
    required int quantity,
    required int unitPriceCents,
    required DateTime bookedAt,
    required bool isLate,
    DateTime? cancelledAt,
  }) = _AdminBooking;

  int get amountCents => quantity * unitPriceCents;

  bool get isCancelled => cancelledAt != null;
}
