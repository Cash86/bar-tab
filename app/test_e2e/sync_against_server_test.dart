// End-to-end sync against a real bar-tab server. Run via `tool/e2e.sh`,
// which starts the server in Docker and passes the dart-defines below.
import 'package:bar_tab/data/api/api_client.dart';
import 'package:bar_tab/data/api/mappers.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/booking_repository_impl.dart';
import 'package:bar_tab/data/repositories/catalog_repository_impl.dart';
import 'package:bar_tab/data/repositories/tabs_repository_impl.dart';
import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/running_total.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const _baseUrl = String.fromEnvironment('E2E_BASE_URL');
const _deviceKey = String.fromEnvironment('E2E_DEVICE_KEY');

final _skipReason = (_baseUrl.isEmpty || _deviceKey.isEmpty)
    ? 'Needs a running server: run app/tool/e2e.sh '
          '(sets E2E_BASE_URL and E2E_DEVICE_KEY)'
    : null;

void main() {
  late AppDatabase db;
  late http.Client httpClient;
  late BarTabApi api;
  late BookingRepositoryImpl bookings;
  late TabsRepositoryImpl tabs;
  late CatalogRepositoryImpl catalogRepo;
  late SyncService sync;
  final clock = SystemClock();
  const uuid = Uuid();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    httpClient = http.Client();
    api = BarTabApi(
      client: httpClient,
      config: const ServerConfig(baseUrl: _baseUrl, deviceKey: _deviceKey),
    );
    bookings = BookingRepositoryImpl(db, clock);
    tabs = TabsRepositoryImpl(db, clock);
    catalogRepo = CatalogRepositoryImpl(db, clock);
    sync = SyncService(
      api: api,
      bookings: bookings,
      tabs: tabs,
      catalog: catalogRepo,
      clock: clock,
      transaction: db.transaction,
    );
  });

  tearDown(() async {
    await sync.dispose();
    httpClient.close();
    await db.close();
  });

  Booking queued(Person p, Drink d, int quantity, int unitPriceCents) =>
      Booking(
        id: uuid.v4(),
        personId: p.id,
        drinkId: d.id,
        quantity: quantity,
        unitPriceCents: unitPriceCents,
        bookedAt: clock.now(),
        status: BookingStatus.queued,
        includedInTabs: false,
      );

  Future<int> serverTab(String personId) async =>
      (await api.getTabs()).tabs[personId] ?? 0;

  test(
    'catalog, booking, idempotent re-sync and stale price against the server',
    () async {
      // Catalog: demo data is visible, umlauts survive the round trip.
      final fetch = await api.getCatalog();
      expect(fetch, isA<CatalogUpdated>());
      final catalog = catalogFromDto((fetch as CatalogUpdated).catalog);
      final person = catalog.persons.firstWhere((p) => p.name == 'Jörg');
      expect(catalog.persons.any((p) => p.name == 'Bärbel'), isTrue);
      expect(catalog.tiers.map((t) => t.name), containsAll(['Mitglieder']));
      final drinks = catalog.drinksFor(person).expand((g) => g.$2).toList();
      expect(drinks.map((d) => d.name), contains('Pils'));

      final pils = drinks.firstWhere((d) => d.name == 'Pils');
      final cola = drinks.firstWhere((d) => d.name == 'Cola');
      final pilsPrice = catalog.priceFor(pils, person)!;
      final colaPrice = catalog.priceFor(cola, person)!;

      final before = await serverTab(person.id);

      // Three bookings with catalog prices.
      final batch = [
        queued(person, pils, 2, pilsPrice),
        queued(person, pils, 1, pilsPrice),
        queued(person, cola, 3, colaPrice),
      ];
      final expected = 3 * pilsPrice + 3 * colaPrice;
      await bookings.addAll(batch);

      await sync.syncNow();

      expect(await bookings.queued(), isEmpty);
      final stored = await (db.select(db.bookings)).get();
      expect(stored, hasLength(3));
      expect(
        stored.map((r) => r.status),
        everyElement(BookingStatus.accepted.name),
      );

      final afterFirst = await serverTab(person.id);
      expect(afterFirst - before, expected);

      // Running total equals the server tab, nothing double-counted.
      final localTab = await tabs.watchTab(person.id).first;
      expect(localTab, afterFirst);
      final notIncluded = await bookings.watchNotIncluded(person.id).first;
      expect(
        runningTotalCents(serverTabCents: localTab, localBookings: notIncluded),
        afterFirst,
      );

      // A second sync posts nothing again: the server tab is unchanged.
      await sync.syncNow();
      expect(await serverTab(person.id), afterFirst);
      expect(await bookings.queued(), isEmpty);

      // Stale price: the server books exactly what the tablet sent.
      final stalePrice = pilsPrice + 7;
      await bookings.addAll([queued(person, pils, 1, stalePrice)]);
      await sync.syncNow();

      final all = await (db.select(db.bookings)).get();
      expect(all, hasLength(4));
      expect(
        all.map((r) => r.status),
        everyElement(BookingStatus.accepted.name),
      );
      expect(await serverTab(person.id), afterFirst + stalePrice);
    },
    skip: _skipReason,
  );
}
