import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking.freezed.dart';

enum BookingStatus { queued, accepted, rejected, conflict }

/// How long a new order stays undoable on the tablet; its bookings are not
/// uploaded before this has passed.
const kUndoWindow = Duration(seconds: 15);

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

    /// Not uploaded before this time (the undo window); `null` = not held.
    DateTime? holdUntil,
  }) = _Booking;
}
