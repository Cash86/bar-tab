// End-to-end sync against a real bar-tab server. Run via `tool/e2e.sh`,
// which starts the server in Docker and passes the dart-defines below.
import 'package:bar_tab/data/api/api_client.dart';
import 'package:bar_tab/data/api/mappers.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/booking_repository_impl.dart';
import 'package:bar_tab/data/repositories/catalog_repository_impl.dart';
import 'package:bar_tab/data/repositories/rankings_repository_impl.dart';
import 'package:bar_tab/data/repositories/tabs_repository_impl.dart';
import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/running_total.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const _baseUrl = String.fromEnvironment('E2E_BASE_URL');
const _deviceKey = String.fromEnvironment('E2E_DEVICE_KEY');
const _adminPin = String.fromEnvironment('E2E_ADMIN_PIN');

final _skipReason =
    (_baseUrl.isEmpty || _deviceKey.isEmpty || _adminPin.isEmpty)
    ? 'Needs a running server: run app/tool/e2e.sh '
          '(sets E2E_BASE_URL, E2E_DEVICE_KEY and E2E_ADMIN_PIN)'
    : null;

void main() {
  late AppDatabase db;
  late http.Client httpClient;
  late BarTabApi api;
  late BookingRepositoryImpl bookings;
  late TabsRepositoryImpl tabs;
  late CatalogRepositoryImpl catalogRepo;
  late RankingsRepositoryImpl rankings;
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
    rankings = RankingsRepositoryImpl(db, clock);
    sync = SyncService(
      api: api,
      bookings: bookings,
      tabs: tabs,
      catalog: catalogRepo,
      rankings: rankings,
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

      // Rankings count bookings (rows), not units: two Pils rows, one Cola.
      final ranked = (await rankings.watch().first)!;
      expect(ranked.persons[person.id]![pils.id], 2);
      expect(ranked.persons[person.id]![cola.id], 1);
      expect(ranked.overall[pils.id], greaterThanOrEqualTo(2));

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

      // Lost response: the tablet never learned the booking was accepted and
      // posts it again; the server answers duplicate, the tab is unchanged.
      final resent = batch.first.id;
      await (db.update(db.bookings)..where((r) => r.id.equals(resent))).write(
        BookingsCompanion(status: Value(BookingStatus.queued.name)),
      );
      expect(await bookings.queued(), hasLength(1));
      await sync.syncNow();
      expect(await bookings.queued(), isEmpty);
      final row = await (db.select(
        db.bookings,
      )..where((r) => r.id.equals(resent))).getSingle();
      expect(row.status, BookingStatus.accepted.name);
      expect(await serverTab(person.id), afterFirst);

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

  test('storno removes a booking from the tab', () async {
    final fetch = await api.getCatalog();
    final catalog = catalogFromDto((fetch as CatalogUpdated).catalog);
    final person = catalog.persons.firstWhere((p) => p.name == 'Jörg');
    final drinks = catalog.drinksFor(person).expand((g) => g.$2).toList();
    final pils = drinks.firstWhere((d) => d.name == 'Pils');
    final price = catalog.priceFor(pils, person)!;

    final before = await serverTab(person.id);
    final booking = queued(person, pils, 2, price);
    await bookings.addAll([booking]);
    await sync.syncNow();
    expect(await serverTab(person.id), before + 2 * price);
    expect(await tabs.watchTab(person.id).first, before + 2 * price);

    final login = await api.openAdminSession(_adminPin);
    expect(login, isA<AdminLoggedIn>());
    final token = (login as AdminLoggedIn).token;

    final listed = await api.listAdminBookings(token, personId: person.id);
    final dto = listed.firstWhere((b) => b.id == booking.id);
    expect(dto.cancelledAt, isNull);

    final cancelled = await api.cancelBooking(token, booking.id);
    expect(cancelled.cancelledAt, isNotNull);

    await sync.syncNow();
    expect(await serverTab(person.id), before);
    expect(await tabs.watchTab(person.id).first, before);

    await expectLater(
      api.cancelBooking(token, booking.id),
      throwsA(
        isA<BookingNotCancellableException>().having(
          (e) => e.reason,
          'reason',
          'already_cancelled',
        ),
      ),
    );

    await api.closeAdminSession(token);
    await expectLater(
      api.pingAdmin(token),
      throwsA(isA<AdminSessionEndedException>()),
    );
  }, skip: _skipReason);
}
