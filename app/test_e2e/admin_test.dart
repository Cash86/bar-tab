// End-to-end admin area against a real bar-tab server. Run via
// `tool/e2e.sh`, which starts the server in Docker and passes the
// dart-defines below. Tests are order-independent: created names carry a
// random suffix and the admin PIN is restored after the PIN test.
import 'dart:math';

import 'package:bar_tab/data/api/api_client.dart';
import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const _baseUrl = String.fromEnvironment('E2E_BASE_URL');
const _deviceKey = String.fromEnvironment('E2E_DEVICE_KEY');
const _deviceKey2 = String.fromEnvironment('E2E_DEVICE_KEY2');
const _adminPin = String.fromEnvironment('E2E_ADMIN_PIN');

final _skipReason =
    (_baseUrl.isEmpty ||
        _deviceKey.isEmpty ||
        _deviceKey2.isEmpty ||
        _adminPin.isEmpty)
    ? 'Needs a running server: run app/tool/e2e.sh '
          '(sets E2E_BASE_URL, E2E_DEVICE_KEY, E2E_DEVICE_KEY2 and '
          'E2E_ADMIN_PIN)'
    : null;

void main() {
  late http.Client httpClient;
  late BarTabApi api;
  final clock = SystemClock();
  const uuid = Uuid();
  final random = Random();

  setUp(() {
    httpClient = http.Client();
    api = BarTabApi(
      client: httpClient,
      config: const ServerConfig(baseUrl: _baseUrl, deviceKey: _deviceKey),
    );
  });

  tearDown(() => httpClient.close());

  String unique(String prefix) =>
      '$prefix${random.nextInt(1 << 20).toRadixString(36)}';

  Future<String> login([String pin = _adminPin]) async {
    final result = await api.openAdminSession(pin);
    expect(result, isA<AdminLoggedIn>());
    return (result as AdminLoggedIn).token;
  }

  Future<CatalogDto> catalog() async =>
      ((await api.getCatalog()) as CatalogUpdated).catalog;

  test('a created person shows up in the catalog with a new ETag', () async {
    final token = await login();
    final before = await catalog();
    final name = unique('P');
    final person = await api.createPerson(
      token,
      PersonWriteDto(
        name: name,
        priceTierId: before.priceTiers.first.id,
        isHidden: false,
        isCollective: false,
      ),
    );

    final after = await catalog();
    expect(after.persons.map((p) => p.id), contains(person.id));
    expect(after.persons.firstWhere((p) => p.id == person.id).name, name);
    expect(after.etag, isNot(before.etag));
    await api.closeAdminSession(token);
  }, skip: _skipReason);

  test(
    'a delivery of 43 units is listed, cancelled and listed as cancelled',
    () async {
      final token = await login();
      final drink = (await catalog()).drinks.first;
      final id = uuid.v4();

      final created = await api.createDeliveries(token, [
        DeliveryInDto(id: id, drinkId: drink.id, quantity: 43),
      ]);
      expect(created.single.quantity, 43);

      // A retried request does not double the delivery.
      await api.createDeliveries(token, [
        DeliveryInDto(id: id, drinkId: drink.id, quantity: 43),
      ]);
      var listed = (await api.listDeliveries(token)).where((d) => d.id == id);
      expect(listed, hasLength(1));
      expect(listed.single.quantity, 43);
      expect(listed.single.cancelledAt, isNull);

      final cancelled = await api.cancelDelivery(token, id);
      expect(cancelled.cancelledAt, isNotNull);
      listed = (await api.listDeliveries(token)).where((d) => d.id == id);
      expect(listed.single.cancelledAt, isNotNull);
      await api.closeAdminSession(token);
    },
    skip: _skipReason,
  );

  test('an event booking for a hidden person is stored with the tier price and '
      'a retry does not double it', () async {
    final token = await login();
    final cat = await catalog();
    final tier = cat.priceTiers.first;
    final drink = cat.drinks.firstWhere(
      (d) => d.prices.containsKey(tier.id) && d.isActive,
    );
    final person = await api.createPerson(
      token,
      PersonWriteDto(
        name: unique('Ev'),
        priceTierId: tier.id,
        isHidden: true,
        isCollective: true,
      ),
    );
    final price = drink.prices[tier.id]!;
    final booking = BookingInDto(
      id: uuid.v4(),
      personId: person.id,
      drinkId: drink.id,
      quantity: 3,
      unitPriceCents: price,
      bookedAt: clock.now(),
    );

    await api.postBookings([booking]);
    await api.postBookings([booking]);

    final listed = await api.listAdminBookings(token, personId: person.id);
    expect(listed, hasLength(1));
    expect(listed.single.id, booking.id);
    expect(listed.single.quantity, 3);
    expect(listed.single.unitPriceCents, price);
    expect((await api.getTabs()).tabs[person.id], 3 * price);
    await api.closeAdminSession(token);
  }, skip: _skipReason);

  test(
    'changing the PIN refuses the old one and accepts the new one',
    () async {
      const newPin = '2580';
      final token = await login();
      var changed = false;
      try {
        expect(
          await api.changeAdminPin(token, '0000', newPin),
          isA<PinWrong>(),
        );
        expect(
          await api.changeAdminPin(token, _adminPin, newPin),
          isA<PinChanged>(),
        );
        changed = true;

        expect(await api.openAdminSession(_adminPin), isA<AdminWrongPin>());
        final newToken = await login(newPin);
        expect(
          await api.changeAdminPin(newToken, newPin, _adminPin),
          isA<PinChanged>(),
        );
        changed = false;
      } finally {
        if (changed) {
          // Restore the original PIN so reruns and other tests still work.
          final t = await login(newPin);
          await api.changeAdminPin(t, newPin, _adminPin);
        }
      }
      await login();
    },
    skip: _skipReason,
  );

  test('re-pairing with a second device key keeps a queued booking and pushes '
      'it once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        syncIntervalProvider.overrideWithValue(null),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final token = await login();
    final cat = await catalog();
    final tier = cat.priceTiers.first;
    final drink = cat.drinks.firstWhere(
      (d) => d.prices.containsKey(tier.id) && d.isActive,
    );
    final price = drink.prices[tier.id]!;
    final person = await api.createPerson(
      token,
      PersonWriteDto(
        name: unique('Rp'),
        priceTierId: tier.id,
        isHidden: false,
        isCollective: false,
      ),
    );

    final pairing = container.read(pairingProvider);
    expect(
      await pairing.pair(
        const ServerConfig(baseUrl: _baseUrl, deviceKey: _deviceKey),
      ),
      PairingResult.success,
    );

    final booking = Booking(
      id: uuid.v4(),
      personId: person.id,
      drinkId: drink.id,
      quantity: 2,
      unitPriceCents: price,
      bookedAt: clock.now(),
      status: BookingStatus.queued,
      includedInTabs: false,
    );
    final repository = container.read(bookingRepositoryProvider);
    await repository.addAll([booking]);

    expect(
      await pairing.pair(
        const ServerConfig(baseUrl: _baseUrl, deviceKey: _deviceKey2),
        repair: true,
      ),
      PairingResult.success,
    );
    expect(await repository.queued(), hasLength(1));
    expect(
      (await container.read(serverConfigProvider.future))!.deviceKey,
      _deviceKey2,
    );

    final sync = container.read(syncServiceProvider)!;
    await sync.syncNow();
    await sync.syncNow();

    expect(await repository.queued(), isEmpty);
    final listed = await api.listAdminBookings(token, personId: person.id);
    expect(listed.map((b) => b.id), [booking.id]);
    expect((await api.getTabs()).tabs[person.id], 2 * price);
    await api.closeAdminSession(token);
  }, skip: _skipReason);
}
