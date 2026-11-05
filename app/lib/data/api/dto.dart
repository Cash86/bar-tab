import 'package:freezed_annotation/freezed_annotation.dart';

part 'dto.freezed.dart';
part 'dto.g.dart';

// Wire DTOs mirroring api/openapi.json. JSON keys are snake_case (build.yaml).
// test/data/api/dto_contract_test.dart fails when these diverge from the schema.

@freezed
abstract class PriceTierDto with _$PriceTierDto {
  const factory PriceTierDto({
    required String id,
    required String name,
    required int sortOrder,
  }) = _PriceTierDto;

  factory PriceTierDto.fromJson(Map<String, dynamic> json) =>
      _$PriceTierDtoFromJson(json);
}

@freezed
abstract class PersonDto with _$PersonDto {
  const factory PersonDto({
    required String id,
    required String name,
    required String priceTierId,
    required bool isHidden,
    required bool isCollective,
    required bool isActive,
  }) = _PersonDto;

  factory PersonDto.fromJson(Map<String, dynamic> json) =>
      _$PersonDtoFromJson(json);
}

@freezed
abstract class GroupDto with _$GroupDto {
  const factory GroupDto({
    required String id,
    required String name,
    required int sortOrder,

    /// "#RRGGBB".
    required String color,
  }) = _GroupDto;

  factory GroupDto.fromJson(Map<String, dynamic> json) =>
      _$GroupDtoFromJson(json);
}

@freezed
abstract class DrinkDto with _$DrinkDto {
  const factory DrinkDto({
    required String id,
    required String name,
    required String groupId,
    required int crateSize,
    required int sortOrder,
    required bool isHidden,
    required bool isActive,
    required Map<String, int> prices,
  }) = _DrinkDto;

  factory DrinkDto.fromJson(Map<String, dynamic> json) =>
      _$DrinkDtoFromJson(json);
}

@freezed
abstract class CatalogDto with _$CatalogDto {
  const factory CatalogDto({
    required List<PriceTierDto> priceTiers,
    required List<PersonDto> persons,
    required List<GroupDto> groups,
    required List<DrinkDto> drinks,
    required String etag,
  }) = _CatalogDto;

  factory CatalogDto.fromJson(Map<String, dynamic> json) =>
      _$CatalogDtoFromJson(json);
}

@freezed
abstract class BookingInDto with _$BookingInDto {
  const factory BookingInDto({
    required String id,
    required String personId,
    required String drinkId,
    required int quantity,
    required int unitPriceCents,
    required DateTime bookedAt,
  }) = _BookingInDto;

  factory BookingInDto.fromJson(Map<String, dynamic> json) =>
      _$BookingInDtoFromJson(json);
}

@freezed
abstract class BookingBatchRequestDto with _$BookingBatchRequestDto {
  const factory BookingBatchRequestDto({required List<BookingInDto> bookings}) =
      _BookingBatchRequestDto;

  factory BookingBatchRequestDto.fromJson(Map<String, dynamic> json) =>
      _$BookingBatchRequestDtoFromJson(json);
}

enum BookingResultStatus {
  @JsonValue('accepted')
  accepted,
  @JsonValue('duplicate')
  duplicate,
  @JsonValue('conflict')
  conflict,
  @JsonValue('rejected')
  rejected,
}

enum BookingRejectReason {
  @JsonValue('unknown_person')
  unknownPerson,
  @JsonValue('unknown_drink')
  unknownDrink,
  @JsonValue('invalid_quantity')
  invalidQuantity,
  @JsonValue('invalid_price')
  invalidPrice,
  @JsonValue('invalid_booked_at')
  invalidBookedAt,
}

@freezed
abstract class BookingResultDto with _$BookingResultDto {
  const factory BookingResultDto({
    required String id,
    required BookingResultStatus status,
    BookingRejectReason? reason,
  }) = _BookingResultDto;

  factory BookingResultDto.fromJson(Map<String, dynamic> json) =>
      _$BookingResultDtoFromJson(json);
}

@freezed
abstract class BookingBatchResponseDto with _$BookingBatchResponseDto {
  const factory BookingBatchResponseDto({
    required List<BookingResultDto> results,
  }) = _BookingBatchResponseDto;

  factory BookingBatchResponseDto.fromJson(Map<String, dynamic> json) =>
      _$BookingBatchResponseDtoFromJson(json);
}

@freezed
abstract class TabsDto with _$TabsDto {
  const factory TabsDto({
    required DateTime periodStartedAt,

    /// Person id to open balance in cents.
    required Map<String, int> tabs,
  }) = _TabsDto;

  factory TabsDto.fromJson(Map<String, dynamic> json) =>
      _$TabsDtoFromJson(json);
}

@freezed
abstract class RankingsDto with _$RankingsDto {
  const factory RankingsDto({
    /// Drink id to number of bookings of all persons.
    required Map<String, int> overall,

    /// Person id to (drink id to number of bookings).
    required Map<String, Map<String, int>> persons,
  }) = _RankingsDto;

  factory RankingsDto.fromJson(Map<String, dynamic> json) =>
      _$RankingsDtoFromJson(json);
}

@freezed
abstract class ErrorDto with _$ErrorDto {
  const factory ErrorDto({required String detail}) = _ErrorDto;

  factory ErrorDto.fromJson(Map<String, dynamic> json) =>
      _$ErrorDtoFromJson(json);
}

enum LockedDetail {
  @JsonValue('locked')
  locked,
}

@freezed
abstract class LockedDto with _$LockedDto {
  const factory LockedDto({
    required LockedDetail detail,
    required int retryAfter,
  }) = _LockedDto;

  factory LockedDto.fromJson(Map<String, dynamic> json) =>
      _$LockedDtoFromJson(json);
}

@freezed
abstract class AdminSessionRequestDto with _$AdminSessionRequestDto {
  const factory AdminSessionRequestDto({required String pin}) =
      _AdminSessionRequestDto;

  factory AdminSessionRequestDto.fromJson(Map<String, dynamic> json) =>
      _$AdminSessionRequestDtoFromJson(json);
}

@freezed
abstract class AdminSessionResponseDto with _$AdminSessionResponseDto {
  const factory AdminSessionResponseDto({
    required String token,
    required int expiresIn,
  }) = _AdminSessionResponseDto;

  factory AdminSessionResponseDto.fromJson(Map<String, dynamic> json) =>
      _$AdminSessionResponseDtoFromJson(json);
}

@freezed
abstract class AdminBookingDto with _$AdminBookingDto {
  const factory AdminBookingDto({
    required String id,
    required String personId,
    required String drinkId,
    required int quantity,
    required int unitPriceCents,
    required DateTime bookedAt,
    required bool isLate,
    DateTime? cancelledAt,
  }) = _AdminBookingDto;

  factory AdminBookingDto.fromJson(Map<String, dynamic> json) =>
      _$AdminBookingDtoFromJson(json);
}

@freezed
abstract class AdminBookingsDto with _$AdminBookingsDto {
  const factory AdminBookingsDto({required List<AdminBookingDto> bookings}) =
      _AdminBookingsDto;

  factory AdminBookingsDto.fromJson(Map<String, dynamic> json) =>
      _$AdminBookingsDtoFromJson(json);
}
