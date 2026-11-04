import 'package:freezed_annotation/freezed_annotation.dart';

part 'rankings.freezed.dart';

/// How often each drink was booked: overall and per person.
@freezed
abstract class DrinkRankings with _$DrinkRankings {
  const factory DrinkRankings({
    /// Drink id to number of bookings of all persons.
    required Map<String, int> overall,

    /// Person id to (drink id to number of bookings).
    required Map<String, Map<String, int>> persons,
  }) = _DrinkRankings;
}
