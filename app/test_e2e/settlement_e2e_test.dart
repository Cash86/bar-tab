// End-to-end settlement against a real bar-tab server. Run via
// `tool/e2e.sh`. The server has no SMTP, so the close reports `skipped`.
import 'package:bar_tab/data/api/api_client.dart';
import 'package:bar_tab/data/api/dto.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const _baseUrl = String.fromEnvironment('E2E_BASE_URL');
const _deviceKey = String.fromEnvironment('E2E_DEVICE_KEY');
const _adminPin = String.fromEnvironment('E2E_ADMIN_PIN');

final _skipReason =
    (_baseUrl.isEmpty || _deviceKey.isEmpty || _adminPin.isEmpty)
    ? 'Needs a running server: run app/tool/e2e.sh'
    : null;

void main() {
  test('opening count, booking, review, close and a second review that opens '
      'with the counts', () async {
    final httpClient = http.Client();
    addTearDown(httpClient.close);
    final api = BarTabApi(
      client: httpClient,
      config: const ServerConfig(baseUrl: _baseUrl, deviceKey: _deviceKey),
    );
    final login = await api.openAdminSession(_adminPin);
    expect(login, isA<AdminLoggedIn>());
    final token = (login as AdminLoggedIn).token;

    final stock = await api.getStock(token);
    expect(stock.openingCountAllowed, isTrue);
    final countList = stock.drinks;
    expect(countList, isNotEmpty);

    final opening = {for (final d in countList) d.drinkId: 50};
    await api.recordOpeningCount(token, opening);

    // One booking at the tier price; the server never re-prices.
    final cat = ((await api.getCatalog()) as CatalogUpdated).catalog;
    final tier = cat.priceTiers.first;
    final person = cat.persons.firstWhere(
      (p) => p.priceTierId == tier.id && !p.isHidden,
    );
    final drink = cat.drinks.firstWhere(
      (d) =>
          d.prices.containsKey(tier.id) &&
          d.isActive &&
          opening.containsKey(d.id),
    );
    await api.postBookings([
      BookingInDto(
        id: const Uuid().v4(),
        personId: person.id,
        drinkId: drink.id,
        quantity: 2,
        unitPriceCents: drink.prices[tier.id]!,
        bookedAt: SystemClock().now(),
      ),
    ]);

    final counts = {
      for (final d in (await api.getStock(token)).drinks)
        d.drinkId: d.drinkId == drink.id ? 47 : 50,
    };
    final review = await api.reviewSettlement(token, counts);
    final line = review.drinks.firstWhere((d) => d.drinkId == drink.id);
    expect(line.opening, 50);
    expect(line.booked, 2);
    expect(line.counted, 47);
    expect(review.grandTotalCents, greaterThan(0));

    final closed = await api.closeSettlement(token, review.token, counts);
    expect(closed.mailStatus, MailStatus.skipped);

    final next = await api.reviewSettlement(token, counts);
    final nextLine = next.drinks.firstWhere((d) => d.drinkId == drink.id);
    expect(nextLine.opening, 47);
    expect(nextLine.booked, 0);
    expect((await api.getStock(token)).openingCountAllowed, isFalse);
    expect((await api.getSettings(token)).lastSettlement, isNotNull);
    await api.closeAdminSession(token);
  }, skip: _skipReason);
}
