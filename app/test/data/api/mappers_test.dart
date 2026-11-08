import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/data/api/mappers.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/rankings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/catalog_fixture.dart';

void main() {
  test('deliveryFromDto maps all fields', () {
    final delivery = deliveryFromDto(
      DeliveryDto(
        id: 'dl',
        drinkId: 'd',
        quantity: 3,
        createdAt: DateTime.utc(2026, 11, 2, 18),
        cancelledAt: DateTime.utc(2026, 11, 3),
      ),
    );
    expect(delivery.id, 'dl');
    expect(delivery.drinkId, 'd');
    expect(delivery.quantity, 3);
    expect(delivery.createdAt, DateTime.utc(2026, 11, 2, 18));
    expect(delivery.cancelledAt, DateTime.utc(2026, 11, 3));
  });

  test('adminBookingFromDto computes amountCents and isCancelled', () {
    final dto = AdminBookingDto(
      id: 'b',
      personId: 'p',
      drinkId: 'd',
      quantity: 3,
      unitPriceCents: 150,
      bookedAt: DateTime.utc(2026, 11, 2, 18),
      isLate: true,
    );
    final open = adminBookingFromDto(dto);
    expect(open.amountCents, 450);
    expect(open.isCancelled, isFalse);
    expect(open.isLate, isTrue);
    final cancelled = adminBookingFromDto(
      dto.copyWith(cancelledAt: DateTime.utc(2026, 11, 3)),
    );
    expect(cancelled.isCancelled, isTrue);
    expect(cancelled.cancelledAt, DateTime.utc(2026, 11, 3));
  });

  catalogToDtoTests();
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

void catalogToDtoTests() {
  test('catalogToDto round-trips the fixture through the domain model', () {
    final dto = CatalogDto.fromJson(catalogFixtureJson);
    final back = catalogToDto(catalogFromDto(dto));
    expect(back, dto);
    expect(back.toJson()['groups'], [
      {'id': 'g1', 'name': 'Beer', 'sort_order': 1, 'color': '#C8A02B'},
    ]);
  });

  test('bookingStatusFromResult maps duplicate to accepted', () {
    expect(
      bookingStatusFromResult(BookingResultStatus.accepted),
      BookingStatus.accepted,
    );
    expect(
      bookingStatusFromResult(BookingResultStatus.duplicate),
      BookingStatus.accepted,
    );
    expect(
      bookingStatusFromResult(BookingResultStatus.conflict),
      BookingStatus.conflict,
    );
    expect(
      bookingStatusFromResult(BookingResultStatus.rejected),
      BookingStatus.rejected,
    );
  });

  test('rankings survive a DTO round trip', () {
    const rankings = DrinkRankings(
      overall: {'d1': 5, 'd2': 1},
      persons: {
        'p1': {'d1': 2},
        'p2': {'d1': 3, 'd2': 1},
      },
    );
    expect(rankingsFromDto(rankingsToDto(rankings)), rankings);
  });
}
