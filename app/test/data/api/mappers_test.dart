import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/data/api/mappers.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/catalog_fixture.dart';

void main() {
  test('colorFromHex converts #RRGGBB to opaque ARGB', () {
    expect(colorFromHex('#C8A02B'), 0xFFC8A02B);
    expect(colorFromHex('#000000'), 0xFF000000);
  });

  test('colorFromHex rejects malformed input', () {
    expect(() => colorFromHex('C8A02B'), throwsFormatException);
    expect(() => colorFromHex('#FFF'), throwsFormatException);
  });

  test('catalogFromDto maps the fixture and keeps the etag', () {
    final dto = CatalogDto.fromJson(catalogFixtureJson);
    final catalog = catalogFromDto(dto);
    expect(catalog.etag, 'abc123');
    expect(catalog.tiers.map((t) => t.id), ['t1', 't2']);
    expect(catalog.persons[1].isCollective, isTrue);
    expect(catalog.groups.single.color, 0xFFC8A02B);
    expect(catalog.drinks.single.prices, {'t1': 150, 't2': 200});
    expect(catalog.drinks.single.crateSize, 20);
  });

  test('CatalogDto round-trips the fixture JSON', () {
    final dto = CatalogDto.fromJson(catalogFixtureJson);
    expect(dto.toJson(), catalogFixtureJson);
  });

  test('bookingToDto serialises booked_at as UTC ISO 8601 with Z', () {
    final booking = Booking(
      id: '6f1c2a52-0b1e-4c53-9d63-3f1f6d2a8e10',
      personId: 'p1',
      drinkId: 'd1',
      quantity: 2,
      unitPriceCents: 150,
      // Non-UTC input: same instant as 18:00Z.
      bookedAt: DateTime.parse('2026-11-02T19:00:00.000+01:00'),
      status: BookingStatus.queued,
      includedInTabs: false,
    );
    final json = bookingToDto(booking).toJson();
    expect(json['booked_at'], '2026-11-02T18:00:00.000Z');
    expect(json['unit_price_cents'], 150);
    expect(json['person_id'], 'p1');
    expect(json.containsKey('status'), isFalse);
  });
}
