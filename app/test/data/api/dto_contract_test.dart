import 'dart:convert';
import 'dart:io';

import 'package:bar_tab/data/api/dto.dart';
import 'package:flutter_test/flutter_test.dart';

/// DTO name, schema name, and instances covering every enum value.
class _Case {
  _Case(this.dto, this.schema, this.variants);
  final String dto;
  final String schema;
  final List<Map<String, dynamic>> variants;
}

final _date = DateTime.utc(2026, 11, 2, 18);

final _cases = <_Case>[
  _Case('PriceTierDto', 'PriceTierOut', [
    const PriceTierDto(id: 't', name: 'n', sortOrder: 1).toJson(),
  ]),
  _Case('PersonDto', 'PersonOut', [
    const PersonDto(
      id: 'p',
      name: 'n',
      priceTierId: 't',
      isHidden: false,
      isCollective: false,
      isActive: true,
    ).toJson(),
  ]),
  _Case('GroupDto', 'GroupOut', [
    const GroupDto(id: 'g', name: 'n', sortOrder: 1, color: '#000000').toJson(),
  ]),
  _Case('DrinkDto', 'DrinkOut', [
    const DrinkDto(
      id: 'd',
      name: 'n',
      groupId: 'g',
      crateSize: 20,
      sortOrder: 1,
      isHidden: false,
      isActive: true,
      prices: {'t': 100},
    ).toJson(),
  ]),
  _Case('CatalogDto', 'CatalogResponse', [
    const CatalogDto(
      priceTiers: [PriceTierDto(id: 't', name: 'n', sortOrder: 1)],
      persons: [],
      groups: [],
      drinks: [],
      etag: 'e',
    ).toJson(),
  ]),
  _Case('RankingsDto', 'RankingsResponse', [
    const RankingsDto(
      overall: {'d': 3},
      persons: {
        'p': {'d': 1},
      },
    ).toJson(),
  ]),
  _Case('BookingInDto', 'BookingIn', [_booking().toJson()]),
  _Case('BookingBatchRequestDto', 'BookingBatchRequest', [
    BookingBatchRequestDto(bookings: [_booking()]).toJson(),
  ]),
  _Case('BookingResultDto', 'BookingResult', [
    for (final s in BookingResultStatus.values)
      BookingResultDto(id: 'b', status: s).toJson(),
    for (final r in BookingRejectReason.values)
      BookingResultDto(
        id: 'b',
        status: BookingResultStatus.rejected,
        reason: r,
      ).toJson(),
  ]),
  _Case('BookingBatchResponseDto', 'BookingBatchResponse', [
    const BookingBatchResponseDto(
      results: [
        BookingResultDto(id: 'b', status: BookingResultStatus.accepted),
      ],
    ).toJson(),
  ]),
  _Case('TabsDto', 'TabsResponse', [
    TabsDto(periodStartedAt: _date, tabs: const {'p': 300}).toJson(),
  ]),
  _Case('ErrorDto', 'ErrorResponse', [const ErrorDto(detail: 'x').toJson()]),
  _Case('LockedDto', 'LockedResponse', [
    for (final d in LockedDetail.values)
      LockedDto(detail: d, retryAfter: 30).toJson(),
  ]),
  _Case('AdminSessionRequestDto', 'AdminSessionRequest', [
    const AdminSessionRequestDto(pin: '1234').toJson(),
  ]),
  _Case('AdminSessionResponseDto', 'AdminSessionResponse', [
    const AdminSessionResponseDto(token: 't', expiresIn: 60).toJson(),
  ]),
  _Case('AdminBookingDto', 'AdminBookingOut', [
    _adminBooking().toJson(),
    _adminBooking(cancelledAt: _date).toJson(),
  ]),
  _Case('AdminBookingsDto', 'AdminBookingsResponse', [
    AdminBookingsDto(bookings: [_adminBooking()]).toJson(),
  ]),
  _Case('PersonWriteDto', 'PersonCreate', [
    const PersonWriteDto(
      name: 'n',
      priceTierId: 't',
      isHidden: false,
      isCollective: false,
    ).toJson(),
  ]),
  _Case('PersonWriteDto', 'PersonUpdate', [
    const PersonWriteDto(
      name: 'n',
      priceTierId: 't',
      isHidden: false,
      isCollective: false,
      isActive: true,
    ).toJson(),
  ]),
  _Case('DrinkWriteDto', 'DrinkCreate', [
    const DrinkWriteDto(
      name: 'n',
      groupId: 'g',
      crateSize: 20,
      isHidden: false,
      isKeg: true,
      prices: {'t': 100},
    ).toJson(),
  ]),
  _Case('DrinkWriteDto', 'DrinkUpdate', [
    const DrinkWriteDto(
      name: 'n',
      groupId: 'g',
      crateSize: 20,
      isHidden: false,
      isKeg: true,
      prices: {'t': 100},
      isActive: true,
    ).toJson(),
  ]),
  _Case('GroupWriteDto', 'GroupWrite', [
    const GroupWriteDto(name: 'n', color: '#000000').toJson(),
  ]),
  _Case('TierWriteDto', 'TierWrite', [const TierWriteDto(name: 'n').toJson()]),
  _Case('OrderWriteDto', 'OrderWrite', [
    const OrderWriteDto(ids: ['a', 'b']).toJson(),
  ]),
  _Case('DeliveryInDto', 'DeliveryIn', [
    const DeliveryInDto(
      id: '6f1c2a52-0b1e-4c53-9d63-3f1f6d2a8e10',
      drinkId: 'd',
      quantity: 3,
    ).toJson(),
  ]),
  _Case('DeliveryBatchRequestDto', 'DeliveryBatchRequest', [
    const DeliveryBatchRequestDto(
      deliveries: [DeliveryInDto(id: 'i', drinkId: 'd', quantity: 3)],
    ).toJson(),
  ]),
  _Case('DeliveryDto', 'DeliveryOut', [
    _delivery().toJson(),
    _delivery(cancelledAt: _date).toJson(),
  ]),
  _Case('DeliveriesDto', 'DeliveriesResponse', [
    DeliveriesDto(deliveries: [_delivery()]).toJson(),
  ]),
  _Case('CountInDto', 'CountIn', [
    const CountInDto(drinkId: 'd', quantity: 3).toJson(),
  ]),
  _Case('CountsRequestDto', 'CountsRequest', [
    const CountsRequestDto(
      counts: [CountInDto(drinkId: 'd', quantity: 3)],
    ).toJson(),
  ]),
  _Case('CloseRequestDto', 'CloseRequest', [
    const CloseRequestDto(
      token: 't',
      counts: [CountInDto(drinkId: 'd', quantity: 3)],
    ).toJson(),
  ]),
  _Case('StockDrinkDto', 'StockDrinkOut', [
    const StockDrinkDto(
      drinkId: 'd',
      name: 'n',
      groupId: 'g',
      groupName: 'gn',
      crateSize: 20,
      expected: 5,
    ).toJson(),
  ]),
  _Case('StockDto', 'StockResponse', [
    const StockDto(
      periodId: 'p',
      openingCountAllowed: true,
      drinks: [],
    ).toJson(),
    const StockDto(
      periodId: null,
      openingCountAllowed: true,
      drinks: [],
    ).toJson(),
  ]),
  _Case('DrinkLineDto', 'DrinkLineOut', [
    const DrinkLineDto(
      drinkId: 'd',
      name: 'n',
      groupId: 'g',
      opening: 1,
      delivered: 2,
      booked: 3,
      expected: 4,
      counted: 5,
      shrinkage: -1,
      valueCents: 6,
      hasPrice: true,
    ).toJson(),
  ]),
  _Case('GroupLineDto', 'GroupLineOut', [
    const GroupLineDto(
      groupId: 'g',
      name: 'n',
      opening: 1,
      delivered: 2,
      booked: 3,
      expected: 4,
      counted: 5,
      shrinkage: -1,
      valueCents: 6,
      hasPrice: false,
    ).toJson(),
  ]),
  _Case('SettlementReviewDto', 'SettlementReviewOut', [
    const SettlementReviewDto(
      token: 't',
      valuationTierName: 'n',
      drinks: [],
      groups: [],
      personsTotalCents: 1,
      hiddenTotalCents: 2,
      grandTotalCents: 3,
      shrinkageTotalCents: 4,
    ).toJson(),
  ]),
  _Case('SettlementCloseDto', 'SettlementCloseOut', [
    for (final s in MailStatus.values)
      SettlementCloseDto(
        periodId: 'p',
        closedAt: _date,
        mailStatus: s,
      ).toJson(),
  ]),
  _Case('SettingsDto', 'SettingsResponse', [
    SettingsDto(
      recipients: const ['a@example.test'],
      valuationTierId: 't',
      effectiveValuationTierId: 't',
      lastSettlement: SettlementCloseDto(
        periodId: 'p',
        closedAt: _date,
        mailStatus: MailStatus.sent,
      ),
    ).toJson(),
    const SettingsDto(
      recipients: [],
      valuationTierId: null,
      effectiveValuationTierId: 't',
      lastSettlement: null,
    ).toJson(),
  ]),
  _Case('RecipientsWriteDto', 'RecipientsWrite', [
    const RecipientsWriteDto(recipients: ['a@example.test']).toJson(),
  ]),
  _Case('ValuationTierWriteDto', 'ValuationTierWrite', [
    const ValuationTierWriteDto(tierId: 't').toJson(),
  ]),
  _Case('ResendDto', 'ResendOut', [
    for (final s in MailStatus.values) ResendDto(mailStatus: s).toJson(),
  ]),
  _Case('PinChangeRequestDto', 'PinChangeRequest', [
    const PinChangeRequestDto(currentPin: '1234', newPin: '5678').toJson(),
  ]),
];

DeliveryDto _delivery({DateTime? cancelledAt}) => DeliveryDto(
  id: 'dl',
  drinkId: 'd',
  quantity: 3,
  createdAt: _date,
  cancelledAt: cancelledAt,
);

BookingInDto _booking() => BookingInDto(
  id: '6f1c2a52-0b1e-4c53-9d63-3f1f6d2a8e10',
  personId: 'p',
  drinkId: 'd',
  quantity: 1,
  unitPriceCents: 100,
  bookedAt: _date,
);

AdminBookingDto _adminBooking({DateTime? cancelledAt}) => AdminBookingDto(
  id: 'b',
  personId: 'p',
  drinkId: 'd',
  quantity: 2,
  unitPriceCents: 150,
  bookedAt: _date,
  isLate: false,
  cancelledAt: cancelledAt,
);

const _ignoredSchemas = {'HTTPValidationError', 'ValidationError'};

Map<String, dynamic> _loadSchemas() {
  final file = File('../api/openapi.json');
  if (!file.existsSync()) {
    fail(
      'Cannot find ../api/openapi.json (cwd: ${Directory.current.path}). '
      'Run flutter test from the app/ directory.',
    );
  }
  final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (doc['components'] as Map<String, dynamic>)['schemas']
      as Map<String, dynamic>;
}

/// Returns (type, nullable, enumValues) for a property schema.
({String? type, bool nullable, Set<String>? enums}) _describe(
  Map<String, dynamic> prop,
) {
  final anyOf = prop['anyOf'] as List?;
  if (anyOf != null) {
    final nonNull = anyOf
        .cast<Map<String, dynamic>>()
        .where((s) => s['type'] != 'null')
        .toList();
    final nullable = nonNull.length != anyOf.length;
    expect(nonNull, hasLength(1), reason: 'unsupported anyOf: $prop');
    final inner = _describe(nonNull.single);
    return (type: inner.type, nullable: nullable, enums: inner.enums);
  }
  return (
    // A $ref points at another object schema.
    type: prop.containsKey(r'$ref') ? 'object' : prop['type'] as String?,
    nullable: false,
    enums: (prop['enum'] as List?)?.cast<String>().toSet(),
  );
}

bool _matches(String? type, Object? value) => switch (type) {
  'string' => value is String,
  'integer' => value is int,
  'boolean' => value is bool,
  'array' => value is List,
  'object' => value is Map,
  _ => false,
};

void main() {
  final schemas = _loadSchemas();

  test('every schema in openapi.json has a DTO in the table', () {
    final covered = _cases.map((c) => c.schema).toSet();
    final expected = schemas.keys.toSet().difference(_ignoredSchemas);
    expect(covered, expected);
  });

  for (final c in _cases) {
    group('${c.dto} vs ${c.schema}', () {
      final schema = schemas[c.schema] as Map<String, dynamic>?;

      test('schema exists', () => expect(schema, isNotNull));
      if (schema == null) return;
      final props = schema['properties'] as Map<String, dynamic>;
      final required = ((schema['required'] as List?) ?? const [])
          .cast<String>();

      test('keys, required and JSON types match', () {
        for (final json in c.variants) {
          expect(json.keys.toSet(), props.keys.toSet());
          expect(json.keys, containsAll(required));
          json.forEach((key, value) {
            final d = _describe(props[key] as Map<String, dynamic>);
            if (value == null) {
              expect(d.nullable, isTrue, reason: '$key must be nullable');
            } else {
              expect(
                _matches(d.type, value),
                isTrue,
                reason: '$key: ${d.type} vs ${value.runtimeType}',
              );
            }
          });
        }
      });

      test('string enums match the schema', () {
        for (final entry in props.entries) {
          final enums = _describe(entry.value as Map<String, dynamic>).enums;
          if (enums == null) continue;
          final seen = {
            for (final json in c.variants)
              if (json[entry.key] != null) json[entry.key] as String,
          };
          expect(seen, enums, reason: 'enum ${entry.key}');
        }
      });
    });
  }
}
