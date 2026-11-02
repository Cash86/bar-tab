import '../../domain/booking.dart';
import '../../domain/catalog.dart';
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
