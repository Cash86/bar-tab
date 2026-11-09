import '../../domain/admin_booking.dart';
import '../../domain/booking.dart';
import '../../domain/catalog.dart';
import '../../domain/delivery.dart';
import '../../domain/rankings.dart';
import 'dto.dart';

/// Converts "#RRGGBB" to an opaque ARGB int.
int colorFromHex(String hex) {
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex);
  if (m == null) throw FormatException('Invalid colour "$hex"');
  return 0xFF000000 | int.parse(m.group(1)!, radix: 16);
}

Catalog catalogFromDto(CatalogDto dto) => Catalog(
  tiers: [
    for (final t in dto.priceTiers)
      PriceTier(id: t.id, name: t.name, sortOrder: t.sortOrder),
  ],
  persons: [
    for (final p in dto.persons)
      Person(
        id: p.id,
        name: p.name,
        priceTierId: p.priceTierId,
        isHidden: p.isHidden,
        isCollective: p.isCollective,
        isActive: p.isActive,
      ),
  ],
  groups: [
    for (final g in dto.groups)
      DrinkGroup(
        id: g.id,
        name: g.name,
        sortOrder: g.sortOrder,
        color: colorFromHex(g.color),
      ),
  ],
  drinks: [
    for (final d in dto.drinks)
      Drink(
        id: d.id,
        name: d.name,
        groupId: d.groupId,
        crateSize: d.crateSize,
        sortOrder: d.sortOrder,
        isHidden: d.isHidden,
        isKeg: d.isKeg,
        isActive: d.isActive,
        prices: Map.of(d.prices),
      ),
  ],
  etag: dto.etag,
);

/// `bookedAt` is converted to UTC so it serialises with a trailing `Z`.
BookingInDto bookingToDto(Booking b) => BookingInDto(
  id: b.id,
  personId: b.personId,
  drinkId: b.drinkId,
  quantity: b.quantity,
  unitPriceCents: b.unitPriceCents,
  bookedAt: b.bookedAt.toUtc(),
);

String hexFromColor(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Inverse of [catalogFromDto]; used to serialise the catalog cache.
CatalogDto catalogToDto(Catalog c) => CatalogDto(
  priceTiers: [
    for (final t in c.tiers)
      PriceTierDto(id: t.id, name: t.name, sortOrder: t.sortOrder),
  ],
  persons: [
    for (final p in c.persons)
      PersonDto(
        id: p.id,
        name: p.name,
        priceTierId: p.priceTierId,
        isHidden: p.isHidden,
        isCollective: p.isCollective,
        isActive: p.isActive,
      ),
  ],
  groups: [
    for (final g in c.groups)
      GroupDto(
        id: g.id,
        name: g.name,
        sortOrder: g.sortOrder,
        color: hexFromColor(g.color),
      ),
  ],
  drinks: [
    for (final d in c.drinks)
      DrinkDto(
        id: d.id,
        name: d.name,
        groupId: d.groupId,
        crateSize: d.crateSize,
        sortOrder: d.sortOrder,
        isHidden: d.isHidden,
        isKeg: d.isKeg,
        isActive: d.isActive,
        prices: Map.of(d.prices),
      ),
  ],
  etag: c.etag,
);

DrinkRankings rankingsFromDto(RankingsDto dto) => DrinkRankings(
  overall: Map.of(dto.overall),
  persons: {for (final e in dto.persons.entries) e.key: Map.of(e.value)},
);

RankingsDto rankingsToDto(DrinkRankings r) => RankingsDto(
  overall: Map.of(r.overall),
  persons: {for (final e in r.persons.entries) e.key: Map.of(e.value)},
);

/// Server result to local booking status; a duplicate counts as accepted.
BookingStatus bookingStatusFromResult(BookingResultStatus s) => switch (s) {
  BookingResultStatus.accepted ||
  BookingResultStatus.duplicate => BookingStatus.accepted,
  BookingResultStatus.conflict => BookingStatus.conflict,
  BookingResultStatus.rejected => BookingStatus.rejected,
};

AdminBooking adminBookingFromDto(AdminBookingDto dto) => AdminBooking(
  id: dto.id,
  personId: dto.personId,
  drinkId: dto.drinkId,
  quantity: dto.quantity,
  unitPriceCents: dto.unitPriceCents,
  bookedAt: dto.bookedAt,
  isLate: dto.isLate,
  cancelledAt: dto.cancelledAt,
);

Delivery deliveryFromDto(DeliveryDto dto) => Delivery(
  id: dto.id,
  drinkId: dto.drinkId,
  quantity: dto.quantity,
  createdAt: dto.createdAt,
  cancelledAt: dto.cancelledAt,
);
