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

/// Body of createPerson (`PersonCreate`) and updatePerson (`PersonUpdate`);
/// [isActive] is only sent on update.
@freezed
abstract class PersonWriteDto with _$PersonWriteDto {
  const factory PersonWriteDto({
    required String name,
    required String priceTierId,
    required bool isHidden,
    required bool isCollective,
    @JsonKey(includeIfNull: false) bool? isActive,
  }) = _PersonWriteDto;

  factory PersonWriteDto.fromJson(Map<String, dynamic> json) =>
      _$PersonWriteDtoFromJson(json);
}

/// Body of createDrink (`DrinkCreate`) and updateDrink (`DrinkUpdate`);
/// [isActive] is only sent on update.
@freezed
abstract class DrinkWriteDto with _$DrinkWriteDto {
  const factory DrinkWriteDto({
    required String name,
    required String groupId,
    required int crateSize,
    required bool isHidden,
    required Map<String, int> prices,
    @JsonKey(includeIfNull: false) bool? isActive,
  }) = _DrinkWriteDto;

  factory DrinkWriteDto.fromJson(Map<String, dynamic> json) =>
      _$DrinkWriteDtoFromJson(json);
}

@freezed
abstract class GroupWriteDto with _$GroupWriteDto {
  const factory GroupWriteDto({
    required String name,

    /// "#RRGGBB".
    required String color,
  }) = _GroupWriteDto;

  factory GroupWriteDto.fromJson(Map<String, dynamic> json) =>
      _$GroupWriteDtoFromJson(json);
}

@freezed
abstract class TierWriteDto with _$TierWriteDto {
  const factory TierWriteDto({required String name}) = _TierWriteDto;

  factory TierWriteDto.fromJson(Map<String, dynamic> json) =>
      _$TierWriteDtoFromJson(json);
}

@freezed
abstract class OrderWriteDto with _$OrderWriteDto {
  const factory OrderWriteDto({required List<String> ids}) = _OrderWriteDto;

  factory OrderWriteDto.fromJson(Map<String, dynamic> json) =>
      _$OrderWriteDtoFromJson(json);
}

@freezed
abstract class DeliveryInDto with _$DeliveryInDto {
  const factory DeliveryInDto({
    required String id,
    required String drinkId,
    required int quantity,
  }) = _DeliveryInDto;

  factory DeliveryInDto.fromJson(Map<String, dynamic> json) =>
      _$DeliveryInDtoFromJson(json);
}

@freezed
abstract class DeliveryBatchRequestDto with _$DeliveryBatchRequestDto {
  const factory DeliveryBatchRequestDto({
    required List<DeliveryInDto> deliveries,
  }) = _DeliveryBatchRequestDto;

  factory DeliveryBatchRequestDto.fromJson(Map<String, dynamic> json) =>
      _$DeliveryBatchRequestDtoFromJson(json);
}

@freezed
abstract class DeliveryDto with _$DeliveryDto {
  const factory DeliveryDto({
    required String id,
    required String drinkId,
    required int quantity,
    required DateTime createdAt,
    DateTime? cancelledAt,
  }) = _DeliveryDto;

  factory DeliveryDto.fromJson(Map<String, dynamic> json) =>
      _$DeliveryDtoFromJson(json);
}

@freezed
abstract class DeliveriesDto with _$DeliveriesDto {
  const factory DeliveriesDto({required List<DeliveryDto> deliveries}) =
      _DeliveriesDto;

  factory DeliveriesDto.fromJson(Map<String, dynamic> json) =>
      _$DeliveriesDtoFromJson(json);
}

@freezed
abstract class PinChangeRequestDto with _$PinChangeRequestDto {
  const factory PinChangeRequestDto({
    required String currentPin,
    required String newPin,
  }) = _PinChangeRequestDto;

  factory PinChangeRequestDto.fromJson(Map<String, dynamic> json) =>
      _$PinChangeRequestDtoFromJson(json);
}

enum MailStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('sent')
  sent,
  @JsonValue('failed')
  failed,
  @JsonValue('skipped')
  skipped,
}

@freezed
abstract class CountInDto with _$CountInDto {
  const factory CountInDto({required String drinkId, required int quantity}) =
      _CountInDto;

  factory CountInDto.fromJson(Map<String, dynamic> json) =>
      _$CountInDtoFromJson(json);
}

@freezed
abstract class CountsRequestDto with _$CountsRequestDto {
  const factory CountsRequestDto({required List<CountInDto> counts}) =
      _CountsRequestDto;

  factory CountsRequestDto.fromJson(Map<String, dynamic> json) =>
      _$CountsRequestDtoFromJson(json);
}

@freezed
abstract class CloseRequestDto with _$CloseRequestDto {
  const factory CloseRequestDto({
    required String token,
    required List<CountInDto> counts,
  }) = _CloseRequestDto;

  factory CloseRequestDto.fromJson(Map<String, dynamic> json) =>
      _$CloseRequestDtoFromJson(json);
}

@freezed
abstract class StockDrinkDto with _$StockDrinkDto {
  const factory StockDrinkDto({
    required String drinkId,
    required String name,
    required String groupId,
    required String groupName,
    required int crateSize,
    required int expected,
  }) = _StockDrinkDto;

  factory StockDrinkDto.fromJson(Map<String, dynamic> json) =>
      _$StockDrinkDtoFromJson(json);
}

@freezed
abstract class StockDto with _$StockDto {
  const factory StockDto({
    required bool openingCountAllowed,
    required List<StockDrinkDto> drinks,
  }) = _StockDto;

  factory StockDto.fromJson(Map<String, dynamic> json) =>
      _$StockDtoFromJson(json);
}

@freezed
abstract class DrinkLineDto with _$DrinkLineDto {
  const factory DrinkLineDto({
    required String drinkId,
    required String groupId,
    required String name,
    required int opening,
    required int delivered,
    required int booked,
    required int expected,
    required int counted,
    required int shrinkage,
    required int valueCents,
    required bool hasPrice,
  }) = _DrinkLineDto;

  factory DrinkLineDto.fromJson(Map<String, dynamic> json) =>
      _$DrinkLineDtoFromJson(json);
}

@freezed
abstract class GroupLineDto with _$GroupLineDto {
  const factory GroupLineDto({
    required String groupId,
    required String name,
    required int opening,
    required int delivered,
    required int booked,
    required int expected,
    required int counted,
    required int shrinkage,
    required int valueCents,
    required bool hasPrice,
  }) = _GroupLineDto;

  factory GroupLineDto.fromJson(Map<String, dynamic> json) =>
      _$GroupLineDtoFromJson(json);
}

@freezed
abstract class SettlementReviewDto with _$SettlementReviewDto {
  const factory SettlementReviewDto({
    required String token,
    required String valuationTierName,
    required List<DrinkLineDto> drinks,
    required List<GroupLineDto> groups,
    required int personsTotalCents,
    required int hiddenTotalCents,
    required int grandTotalCents,
    required int shrinkageTotalCents,
  }) = _SettlementReviewDto;

  factory SettlementReviewDto.fromJson(Map<String, dynamic> json) =>
      _$SettlementReviewDtoFromJson(json);
}

@freezed
abstract class SettlementCloseDto with _$SettlementCloseDto {
  const factory SettlementCloseDto({
    required String periodId,
    required DateTime closedAt,
    required MailStatus mailStatus,
  }) = _SettlementCloseDto;

  factory SettlementCloseDto.fromJson(Map<String, dynamic> json) =>
      _$SettlementCloseDtoFromJson(json);
}

@freezed
abstract class SettingsDto with _$SettingsDto {
  const factory SettingsDto({
    required List<String> recipients,
    required String? valuationTierId,
    required String effectiveValuationTierId,
    required SettlementCloseDto? lastSettlement,
  }) = _SettingsDto;

  factory SettingsDto.fromJson(Map<String, dynamic> json) =>
      _$SettingsDtoFromJson(json);
}

@freezed
abstract class RecipientsWriteDto with _$RecipientsWriteDto {
  const factory RecipientsWriteDto({required List<String> recipients}) =
      _RecipientsWriteDto;

  factory RecipientsWriteDto.fromJson(Map<String, dynamic> json) =>
      _$RecipientsWriteDtoFromJson(json);
}

@freezed
abstract class ValuationTierWriteDto with _$ValuationTierWriteDto {
  const factory ValuationTierWriteDto({required String tierId}) =
      _ValuationTierWriteDto;

  factory ValuationTierWriteDto.fromJson(Map<String, dynamic> json) =>
      _$ValuationTierWriteDtoFromJson(json);
}

@freezed
abstract class ResendDto with _$ResendDto {
  const factory ResendDto({required MailStatus mailStatus}) = _ResendDto;

  factory ResendDto.fromJson(Map<String, dynamic> json) =>
      _$ResendDtoFromJson(json);
}
