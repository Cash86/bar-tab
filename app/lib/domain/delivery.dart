import 'package:freezed_annotation/freezed_annotation.dart';

part 'delivery.freezed.dart';

/// A stock delivery; cancelled ones stay in the list.
@freezed
abstract class Delivery with _$Delivery {
  const factory Delivery({
    required String id,
    required String drinkId,
    required int quantity,
    required DateTime createdAt,
    DateTime? cancelledAt,
  }) = _Delivery;
}
