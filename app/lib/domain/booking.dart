import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking.freezed.dart';

enum BookingStatus { queued, accepted, rejected, conflict }

@freezed
abstract class Booking with _$Booking {
  const factory Booking({
    required String id,
    required String personId,
    required String drinkId,
    required int quantity,
    required int unitPriceCents,
    required DateTime bookedAt,
    required BookingStatus status,
    required bool includedInTabs,
  }) = _Booking;
}
