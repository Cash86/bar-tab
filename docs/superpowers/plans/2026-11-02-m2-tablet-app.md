# Milestone 2 — Tablet App (booking) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter Android tablet app that pairs with the M1 server, shows the name list and drink selection exactly as approved, records bookings offline-first in a local queue, syncs them idempotently, and shows each person's running total — plus the server-side contract polish the app's DTOs depend on.

**Architecture:** `app/lib/` split into `domain/` (pure Dart: entities, order logic, running total, repository interfaces, `Clock`), `data/` (HTTP client + DTOs, Drift DB, repositories, sync service, secure config storage) and `presentation/` (Riverpod providers, screens, widgets, theme). The app never re-implements money rules: it only sums stored prices (spec §4.5). The admin area is milestone 3; this app has no admin entry yet.

**Tech Stack:** Flutter 3.44 / Dart 3.12, flutter_riverpod 3, freezed 3 + json_serializable, drift 2 + sqlite3_flutter_libs, http 1 (`MockClient` in tests), flutter_secure_storage, wakelock_plus, uuid 4, intl + flutter_localizations, mocktail, fake_async. Dependencies are added with `flutter pub add` so the resolver picks current compatible versions; `pubspec.lock` is committed.

**Spec:** `docs/superpowers/specs/2026-11-02-bar-tab-design.md` (§3 domain, §4.1 name list, §4.2 drink selection, §4.4 first start, §4.5 offline, §5 API, §8 rules). Approved mockups are described in the spec; the colour tokens below are taken from them.

## Global Constraints

- Repo language English; UI strings German, only via `app/lib/l10n/app_de.arb` (`flutter gen-l10n`), keys `screen.section.purpose` style in camelCase (e.g. `drinkSelectionUndoButton`).
- Nothing club-specific in code: tiers, groups, drinks, persons and colours come from the server catalog. Test data is invented.
- Money is integer cents (`int`); never `double` for money. Display via `intl` `NumberFormat.currency(locale: 'de_DE', symbol: '€')`.
- The unit price stored with a booking is the price shown when the drink was tapped; it is final.
- No `DateTime.now()` outside `app/lib/domain/clock.dart`; everything takes a `Clock`.
- Booking ids are UUID v4 strings generated on the tablet; `booked_at` is sent as ISO 8601 UTC with `Z`.
- Layering: `domain/` imports no Flutter, no `data/`, no `presentation/`; `presentation/` never imports `data/` except through providers in `presentation/providers.dart`.
- Every Drift schema change ships a migration + schema dump (`drift_dev schema dump`) — schema v1 here.
- `flutter analyze` (no issues) and `dart format --set-exit-if-changed .` clean; `flutter test` green. Run from `app/` via `app/tool/check.sh`.
- Landscape only; target device a ~10" Android tablet; widget tests run at logical size 1280×800.
- TDD; never weaken an existing test. Conventional Commits; each message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Design tokens (from the approved mockups)

| Token | Value |
|---|---|
| bottle (background) | `#16302A` |
| bottle2 (tile) | `#1E3D35` |
| bottle3 (button/rail) | `#2A4C43` |
| paper (text, sheets) | `#F2EADB` |
| muted | `#9FB2AA` |
| tier palette (by tier `sort_order` index, cycling) | `#E3A33A`, `#72B8DE`, `#C79BF0`, `#9CC46A` |
| collective accent | `#9CC46A` |
| font | Archivo (variable, bundled under `app/assets/fonts/` with its OFL licence) |

Group colours come from the catalog (`GroupOut.color`).

## Review Focus

1. The tablet is offline when a booking is made → it is stored locally, the header total includes it immediately, and it reaches the server exactly once after the connection returns. (Tasks 6, 7, 12)
2. The server answers an item with `rejected` or `conflict` → the booking is not silently dropped: it stays in the local DB with that status, is excluded from the running total, and the sync indicator shows the count. (Task 7, 9)
3. The app goes to the background (or the screen is left) while an order is pending → the pending order is booked immediately, not lost. (Task 10)
4. The catalog changes while an order is pending (price change, drink deactivated) → the order books with the price shown at tap time; the next order uses the new catalog. (Tasks 3, 10)
5. The device key is revoked (server answers 401) → nothing is deleted, the queue keeps growing, and the indicator says the device is not authorised. (Tasks 5, 7, 9)

---

## File Structure

```
server/bartab/api/deps.py, schemas.py, routes_*.py, main.py     (Task 1, contract polish)
api/openapi.json                                                  (regenerated)
.github/workflows/app.yml
app/
  pubspec.yaml, analysis_options.yaml, l10n.yaml
  tool/check.sh                         analyze + format check + test
  tool/e2e.sh                           server in Docker + e2e tests
  assets/fonts/Archivo*.ttf, assets/fonts/OFL.txt
  android/…                             app id dev.bartab.app, label "bar-tab"
  lib/
    main.dart                           bootstrap, ProviderScope, kiosk setup
    app.dart                            MaterialApp, theme, l10n, routing by config state
    l10n/app_de.arb
    domain/
      clock.dart                        Clock, SystemClock, FixedClock
      catalog.dart                      PriceTier, Person, DrinkGroup, Drink, Catalog (+ queries)
      booking.dart                      Booking, BookingStatus
      order.dart                        OrderDraft (pending order rules)
      running_total.dart                runningTotalCents(...)
      repositories.dart                 abstract CatalogRepository, BookingRepository, TabsRepository, ServerConfigRepository
      sync_state.dart                   SyncState (pending, failed, unauthorised, lastSuccess)
    data/
      api/dto.dart                      freezed DTOs mirroring api/openapi.json
      api/mappers.dart                  DTO → domain
      api/api_client.dart               BarTabApi (http), ApiException hierarchy
      db/database.dart                  Drift DB (tables, v1)
      db/schema/                        drift schema dumps (committed)
      repositories/…_impl.dart          Drift/secure-storage implementations
      sync/sync_service.dart            push queue, pull catalog/tabs, scheduling
    presentation/
      providers.dart                    all Riverpod wiring
      theme.dart                        tokens, ThemeData, text styles
      format.dart                       euro formatting
      setup/setup_screen.dart
      names/name_list_screen.dart, names/name_tile.dart
      drinks/drink_selection_screen.dart, drinks/drink_tile.dart,
      drinks/order_bar.dart, drinks/quantity_sheet.dart, drinks/keypad.dart,
      drinks/order_controller.dart
      common/sync_indicator.dart
  test/  (mirrors lib/; fixtures in test/fixtures/)
  test_e2e/sync_against_server_test.dart
```

---

### Task 1: Server — make the OpenAPI contract client-ready

**Files:**
- Modify: `server/bartab/api/deps.py`, `server/bartab/api/schemas.py`, `server/bartab/api/routes_admin_session.py`, `server/bartab/api/routes_catalog.py`, `server/bartab/api/routes_bookings.py`, `server/bartab/api/routes_health.py`, `server/bartab/main.py`, `api/openapi.json`
- Test: `server/tests/api/test_openapi_shape.py`, `server/tests/api/test_admin_session.py`

**Interfaces:**
- Produces (contract the app relies on):
  - `components.securitySchemes`: `deviceKey` (HTTP bearer) and `adminToken` (API key in header `X-Admin-Token`). Device-auth operations declare `security: [{deviceKey: []}]`; admin ones `[{deviceKey: [], adminToken: []}]`; health declares none. The raw `authorization` / `x-admin-token` header parameters disappear from operations. Runtime behaviour and detail strings stay identical (`invalid_device_key`, `admin_session_required`).
  - Schema `ErrorResponse {detail: str}` and `LockedResponse {detail: "locked", retry_after: int}`; documented responses: every device-auth op 401 → `ErrorResponse`; `POST /admin/session` 401 → `ErrorResponse`, 429 → `LockedResponse`; `GET /catalog` 304 (no body) with header `ETag`.
  - operationIds: `getHealth`, `openAdminSession`, `pingAdmin`, `getCatalog`, `postBookings`, `getTabs` (set via `generate_unique_id_function` using the route function's explicit `name=`).
  - `AdminSessionRequest.pin`: `Field(pattern=r"^\d{4,8}$")` → malformed PIN is 422 and does **not** consume a lockout attempt.

- [ ] **Step 1: Write failing tests** — `test_openapi_shape.py`: security schemes exist; `/api/v1/catalog` get has `operationId == "getCatalog"` and `security == [{"deviceKey": []}]` and no parameter named `authorization`; `/api/v1/admin/session` documents 401 and 429 with the two schemas; `/api/v1/catalog` documents 304 with `ETag` header; set of operationIds equals the six above. `test_admin_session.py`: PIN `"12ab"` → 422; five malformed PINs followed by the correct PIN → 200 (no lockout).
- [ ] **Step 2: Run** `server/tool/test.sh tests/api` → FAIL.
- [ ] **Step 3: Implement** with `fastapi.security.HTTPBearer(auto_error=False)` and `APIKeyHeader(name="X-Admin-Token", auto_error=False)` inside `require_device` / `require_admin` (keep the existing constant-time matching and 401 details); `responses=` on routes; `name=` on each route + `generate_unique_id_function=lambda route: route.name` in `create_app`.
- [ ] **Step 4: Regenerate** `server/tool/export_openapi.py`; full `server/tool/test.sh` → PASS (contract test included).
- [ ] **Step 5: Commit** `feat(server): document auth, errors and operation ids in the API contract`

---

### Task 2: App scaffold, theme, l10n, check script, CI

**Files:**
- Create: `app/` via `flutter create --org dev.bartab --project-name bar_tab --platforms android,linux app`, then: `app/analysis_options.yaml` (flutter_lints + rules: `prefer_const_constructors`, `prefer_final_locals`, `unawaited_futures`, `avoid_print`, `always_declare_return_types`; `strict-casts`, `strict-inference`, `strict-raw-types`; exclude `**/*.g.dart`, `**/*.freezed.dart`), `app/l10n.yaml`, `app/lib/l10n/app_de.arb`, `app/lib/presentation/theme.dart`, `app/lib/presentation/format.dart`, `app/lib/domain/clock.dart`, `app/lib/app.dart`, `app/lib/main.dart`, `app/assets/fonts/` (Archivo variable TTF + OFL.txt from the Google Fonts repo), `app/tool/check.sh`, `.github/workflows/app.yml`
- Modify: `.gitignore` (Flutter build outputs), `README.md` (App development section), `CLAUDE.md` (app commands)
- Test: `app/test/presentation/format_test.dart`, `app/test/domain/clock_test.dart`, `app/test/app_smoke_test.dart`

**Interfaces:**
- Produces: `abstract interface class Clock { DateTime now(); }` (UTC), `SystemClock`, `FixedClock(DateTime)` with `advance(Duration)`; `String formatCents(int cents)` → `"1,15 €"`; `BarTabTheme` with the tokens above as `static const Color`s and `ThemeData get data`; `BarTabApp` widget (MaterialApp with `AppLocalizations`, locale `de`, home = placeholder until Task 8). Android: label `bar-tab`, `screenOrientation="sensorLandscape"` on the activity.
- `app/tool/check.sh`: `flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter gen-l10n && flutter analyze && dart format --set-exit-if-changed lib test test_e2e && flutter test`.
- CI `app.yml`: on PR and push to main with paths `app/**`, `api/**`, `.github/workflows/app.yml`; `subosito/flutter-action` pinned to Flutter 3.44.8; runs `app/tool/check.sh`.

- [ ] **Step 1: Failing tests** — `formatCents(115) == "1,15 €"`, `formatCents(0) == "0,00 €"`, `formatCents(123456) == "1.234,56 €"` (use ` `-aware comparison if intl emits a NBSP — assert on the exact string intl produces for `de_DE` and document it); `FixedClock.advance`; smoke test pumps `BarTabApp` and finds the German placeholder text from the arb.
- [ ] **Step 2–4:** RED → implement → `app/tool/check.sh` GREEN.
- [ ] **Step 5: Commit** `chore(app): scaffold Flutter app with theme, l10n and CI`

---

### Task 3: Domain — catalog, booking, order rules, running total

**Files:**
- Create: `app/lib/domain/catalog.dart`, `booking.dart`, `order.dart`, `running_total.dart`, `repositories.dart`, `sync_state.dart`
- Test: `app/test/domain/catalog_test.dart`, `order_test.dart`, `running_total_test.dart`

**Interfaces:**
- Produces (all `freezed` or plain immutable classes, pure Dart):
  - `PriceTier(id, name, sortOrder)`, `Person(id, name, priceTierId, isHidden, isCollective, isActive)`, `DrinkGroup(id, name, sortOrder, color /* int ARGB */)`, `Drink(id, name, groupId, crateSize, sortOrder, isHidden, isActive, prices /* Map<String,int> tierId→cents */)`, `Catalog(tiers, persons, groups, drinks, etag)`.
  - `Catalog` queries: `List<Person> collectiveAccounts()` (active, not hidden, collective; by name); `List<(PriceTier, List<Person>)> personsByTier()` (tiers by sortOrder; active, not hidden, not collective; persons by name, tie by id; tiers without visible persons omitted); `List<(DrinkGroup, List<Drink>)> drinksFor(Person p)` (groups by sortOrder; drinks active, not hidden, with a price for `p.priceTierId`, by sortOrder then name; empty groups omitted); `int? priceFor(Drink d, Person p)`.
  - `enum BookingStatus { queued, accepted, rejected, conflict }`; `Booking(id, personId, drinkId, quantity, unitPriceCents, bookedAt, status, includedInTabs)`.
  - `OrderDraft` (immutable): `OrderDraft.empty(personId)`, `lines` (ordered `List<OrderLine(drinkId, quantity, unitPriceCents)>` in first-tap order), `TapResult tap(String drinkId, int unitPriceCents)` returning the new draft and `bool openQuantitySheet` (true exactly when that drink's quantity reaches 3 by tapping), `OrderDraft setQuantity(String drinkId, int quantity)` (0 removes the line; 1..999 allowed; outside → `ArgumentError`), `int totalCents`, `bool isEmpty`. A line's price is fixed at its first tap (Review Focus 4).
  - `int runningTotalCents({required int serverTabCents, required Iterable<Booking> localBookings})` = `serverTabCents` + Σ `quantity × unitPriceCents` over local bookings with `status ∈ {queued, accepted}` and `includedInTabs == false`.
  - Repository interfaces (`repositories.dart`):
    `CatalogRepository { Future<Catalog?> cached(); Future<void> save(Catalog); }`,
    `BookingRepository { Future<void> addAll(List<Booking>); Future<List<Booking>> queued({int limit}); Future<void> applyResults(Map<String, BookingStatus>); Future<void> markIncludedInTabs(Set<String> ids); Stream<List<Booking>> watchNotIncluded(String personId); Stream<SyncCounts> watchCounts(); }` (`SyncCounts(queued, failed)` where failed = rejected + conflict),
    `TabsRepository { Future<void> save(Map<String,int> tabs); Stream<int> watchTab(String personId); }`,
    `ServerConfigRepository { Future<ServerConfig?> load(); Future<void> save(ServerConfig); }` with `ServerConfig(baseUrl, deviceKey)`.
  - `SyncState(queued, failed, isUnauthorised, isOffline, lastSuccessAt)`.

- [ ] **Step 1: Failing tests**
  - catalog: table test for `personsByTier` (two tiers, hidden/inactive/collective persons excluded, tie on name ordered by id, empty tier omitted); `collectiveAccounts`; `drinksFor` excludes hidden/inactive/no-price drinks and empty groups, orders correctly; `priceFor` returns the tier price or null.
  - order: tap once → qty 1, sheet false; tap twice → 2, false; third tap → 3, **true**; fourth tap → 4, false; two drinks keep first-tap order; price fixed at first tap even if a later tap passes a different price; `setQuantity(d, 0)` removes; `setQuantity(d, 1000)` throws; `totalCents` = Σ qty×price.
  - running total: table test — queued counts, accepted-not-included counts, accepted-included excluded, rejected and conflict excluded, other person's bookings never passed in.
- [ ] **Step 2–4:** RED → implement → GREEN (`flutter test test/domain`).
- [ ] **Step 5: Commit** `feat(app): add domain model, order rules and running total`

---

### Task 4: DTOs, mappers and contract test

**Files:**
- Create: `app/lib/data/api/dto.dart`, `app/lib/data/api/mappers.dart`
- Test: `app/test/data/api/dto_contract_test.dart`, `app/test/data/api/mappers_test.dart`, `app/test/fixtures/catalog_fixture.dart`

**Decision (deviation from spec §5 wording "DTOs are generated"):** DTOs are hand-written `freezed` + `json_serializable` classes, and a contract test parses `../api/openapi.json` and fails on any divergence. Reason: 12 small schemas; a Dart OpenAPI generator adds a toolchain whose OpenAPI 3.1 support is uneven, while the test gives the same guarantee the spec asks for ("a test fails when app and schema diverge").

**Interfaces:**
- Produces DTOs with snake_case JSON keys (`@JsonKey(name: ...)` or `fieldRename: FieldRename.snake` in `build.yaml`): `PriceTierDto`, `PersonDto`, `GroupDto`, `DrinkDto`, `CatalogDto`, `BookingInDto`, `BookingBatchRequestDto`, `BookingResultDto` (`status` and `reason` as Dart enums with `@JsonValue` strings), `BookingBatchResponseDto`, `TabsDto`, `ErrorDto`, `LockedDto`, `AdminSessionRequestDto`, `AdminSessionResponseDto`.
- `Catalog catalogFromDto(CatalogDto)` (colour `"#RRGGBB"` → `0xFFRRGGBB`), `BookingInDto bookingToDto(Booking)` (`booked_at` UTC ISO with `Z`).
- Contract test algorithm: load `../api/openapi.json`; for each pair `(DtoName, SchemaName)` in a table, build a sample instance, `toJson()`, and assert: key set == schema `properties` keys; every schema `required` key present; JSON type of each value matches the schema type (`string`/`integer`/`boolean`/`array`/`object`, `anyOf` with `null` = nullable); for string enums (`enum` in schema) the Dart enum's `@JsonValue` set equals the schema's enum set. Also assert every schema under `components.schemas` except `HTTPValidationError`/`ValidationError` appears in the table.

- [ ] **Step 1: Failing tests** — contract test as above; mappers: hex colour conversion, booking `booked_at` serialises as `2026-11-02T18:00:00.000Z` (or without millis — pin whatever the server accepts, it parses both), `fromJson` of a real catalog JSON fixture (copy of the server's demo seed shape, invented values) round-trips.
- [ ] **Step 2–4:** RED → `dart run build_runner build` + implement → GREEN.
- [ ] **Step 5: Commit** `feat(app): add API DTOs with OpenAPI contract test`

---

### Task 5: API client

**Files:**
- Create: `app/lib/data/api/api_client.dart`
- Test: `app/test/data/api/api_client_test.dart`

**Interfaces:**
- Consumes: DTOs (Task 4), `ServerConfig` (Task 3).
- Produces: `class BarTabApi { BarTabApi({required http.Client client, required ServerConfig config}); Future<CatalogFetch> getCatalog({String? etag}); Future<List<BookingResultDto>> postBookings(List<BookingInDto>); Future<TabsDto> getTabs(); }` with `sealed class CatalogFetch` = `CatalogUnchanged()` | `CatalogUpdated(CatalogDto)`; base URL joined with `/api/v1/...`; header `Authorization: Bearer <deviceKey>`; 10 s timeout.
- `sealed class ApiException implements Exception`: `UnauthorisedException` (401), `NetworkException` (socket/timeout/`http.ClientException`), `ServerException(int status)` (5xx and unexpected 4xx), `ContractException` (unparseable body).

- [ ] **Step 1: Failing tests** with `http/testing.dart` `MockClient`: sends bearer header and correct paths; `If-None-Match` sent when etag given, 304 → `CatalogUnchanged`; 200 → `CatalogUpdated`; `postBookings` posts `{"bookings": [...]}` and returns results in order; 401 → `UnauthorisedException`; 503 → `ServerException(503)`; thrown `SocketException`/timeout → `NetworkException`; HTML body on 200 → `ContractException`; base URL with and without trailing slash both work.
- [ ] **Step 2–4:** RED → implement → GREEN.
- [ ] **Step 5: Commit** `feat(app): add HTTP client for the bar-tab API`

---

### Task 6: Local database and repositories

**Files:**
- Create: `app/lib/data/db/database.dart`, `app/lib/data/repositories/catalog_repository_impl.dart`, `booking_repository_impl.dart`, `tabs_repository_impl.dart`, `server_config_repository_impl.dart`, `app/lib/data/db/schema/drift_schema_v1.json` (via `dart run drift_dev schema dump`)
- Test: `app/test/data/db/database_test.dart`, `app/test/data/repositories/*_test.dart`

**Interfaces:**
- Produces: `AppDatabase` (Drift, `schemaVersion 1`) with tables:
  - `CatalogCache(id INTEGER PK CHECK id=1, json TEXT, etag TEXT, savedAt DATETIME)` — the whole catalog as JSON (it is small and only read whole).
  - `Bookings(id TEXT PK, personId, drinkId, quantity INT, unitPriceCents INT, bookedAt DATETIME, status TEXT, includedInTabs BOOL default false, createdAt, updatedAt)` with index on `(status)` and `(personId, includedInTabs)`.
  - `Tabs(personId TEXT PK, cents INT, fetchedAt DATETIME)`.
  - Constructor `AppDatabase(QueryExecutor e)`; production opens `bar_tab.sqlite` in the app documents dir via `drift_flutter`/`NativeDatabase.createInBackground`; tests use `NativeDatabase.memory()`.
- Repository implementations of the Task 3 interfaces. `BookingRepository.queued(limit)` returns oldest `bookedAt` first. `applyResults`: `accepted`/`duplicate` → accepted, `rejected` → rejected, `conflict` → conflict. `TabsRepository.save` replaces all rows in one transaction. `ServerConfigRepositoryImpl` uses `flutter_secure_storage` (keys `server_base_url`, `device_key`) behind a tiny `SecureStore` interface so tests use an in-memory fake.
- Timestamps via injected `Clock`.

- [ ] **Step 1: Failing tests** — schema v1 dump test (`drift_dev` `SchemaVerifier` validates a fresh DB against the dump); catalog save/load round-trip incl. etag; bookings: `addAll` then `queued` order and limit; `applyResults` status mapping; `watchNotIncluded(personId)` emits after insert and after `markIncludedInTabs`; `watchCounts` reflects queued/failed; tabs replace semantics; config save/load via fake store; `load()` returns null when unset.
- [ ] **Step 2–4:** RED → implement (+ `build_runner`) → GREEN.
- [ ] **Step 5: Commit** `feat(app): add local database and repositories`

---

### Task 7: Sync service

**Files:**
- Create: `app/lib/data/sync/sync_service.dart`
- Test: `app/test/data/sync/sync_service_test.dart`

**Interfaces:**
- Consumes: `BarTabApi`, the four repositories, `Clock`.
- Produces: `class SyncService { Future<void> syncNow(); void start(); void stop(); Stream<SyncState> get state; }`.
  - `syncNow()` (never runs twice concurrently — a second call while running awaits the running one): (1) push: repeatedly take `queued(limit: 200)`, `postBookings`, `applyResults` until the queue is empty or an error occurs; (2) tabs: remember the ids of bookings with status accepted and `includedInTabs == false` **before** calling `getTabs`, then save tabs and `markIncludedInTabs(thoseIds)` (a booking accepted after the fetch started is not marked, so it is never double-counted or dropped); (3) catalog: `getCatalog(etag: cached?.etag)`, save on `CatalogUpdated`.
  - Errors: `UnauthorisedException` → state `isUnauthorised = true`, stop this run, keep everything; `NetworkException` → `isOffline = true`; `ServerException`/`ContractException` → logged via `debugPrint`-free logger (`package:logging` or a no-op `Logger` interface), state unchanged except `lastSuccessAt` not updated. A successful run clears `isUnauthorised`/`isOffline` and sets `lastSuccessAt = clock.now()`.
  - `start()`: runs `syncNow()` immediately, then every 30 s (`Timer.periodic`, injectable `Duration` for tests); `stop()` cancels.
  - `state` combines `BookingRepository.watchCounts()` with the flags.

- [ ] **Step 1: Failing tests** (fake API implementing a `BarTabApi`-shaped interface or `MockClient`-backed real client; in-memory DB repositories):
  - 450 queued bookings → three POSTs of 200/200/50, all accepted.
  - mixed results: accepted/duplicate → accepted, rejected → rejected, conflict → conflict; **RF2:** rejected/conflict stay in DB and `state.failed == 2`.
  - **RF1:** network failure on first run → bookings stay queued, `isOffline`; second run succeeds → each id posted exactly once overall.
  - tabs: booking accepted before `getTabs` is marked included; a booking added while `getTabs` is in flight (fake delays the response and the test inserts + pushes another) is not marked.
  - catalog 304 keeps cache; 200 replaces it.
  - **RF5:** 401 → `isUnauthorised`, nothing deleted, queue unchanged; later success clears the flag.
  - concurrent `syncNow()` calls → one HTTP push sequence.
  - `start()` with `fake_async`: runs at t=0 and every 30 s; `stop()` stops it.
- [ ] **Step 2–4:** RED → implement → GREEN.
- [ ] **Step 5: Commit** `feat(app): add offline-first sync service`

---

### Task 8: Providers, first-start setup and routing

**Files:**
- Create: `app/lib/presentation/providers.dart`, `app/lib/presentation/setup/setup_screen.dart`
- Modify: `app/lib/app.dart`, `app/lib/main.dart`, `app/lib/l10n/app_de.arb`
- Test: `app/test/presentation/setup/setup_screen_test.dart`, `app/test/presentation/app_routing_test.dart`, `app/test/fixtures/fakes.dart`

**Interfaces:**
- Produces providers (Riverpod 3, all overridable in tests): `clockProvider`, `databaseProvider`, `serverConfigRepositoryProvider`, `serverConfigProvider` (AsyncNotifier: load/save), `httpClientProvider`, `apiProvider` (null while unconfigured), repository providers, `syncServiceProvider` (started when config exists, disposed with the container), `syncStateProvider` (StreamProvider), `catalogProvider` (StreamProvider/AsyncNotifier fed by cache, refreshed after sync), `runningTotalProvider.family(personId)` (combines `TabsRepository.watchTab` and `BookingRepository.watchNotIncluded` via `runningTotalCents`).
- Setup screen: fields "Server-Adresse" and "Geräteschlüssel" (obscured), button "Verbinden". On submit: validate URL (http/https, host present) locally; then `GET /catalog` with the entered values — 200 → save config, save catalog, go to name list; 401 → inline error "Geräteschlüssel ungültig"; network error → "Server nicht erreichbar"; invalid URL → "Adresse ungültig". Button disabled while checking. All strings from arb.
- Routing in `BarTabApp`: config loading → splash (progress); no config → setup; config → name list (Task 9 widget; placeholder until then is acceptable inside this task only if Task 9's screen does not exist yet — create the `NameListScreen` class stub here and fill it in Task 9).

- [ ] **Step 1: Failing tests** — routing: no config → setup screen; saved config → name list; setup: each error case shows its message; success saves config (fake repo receives exact values, trailing slash trimmed) and navigates; button disabled while the request is pending.
- [ ] **Step 2–4:** RED → implement → GREEN.
- [ ] **Step 5: Commit** `feat(app): add first-start pairing and app wiring`

---

### Task 9: Name list screen and sync indicator

**Files:**
- Modify: `app/lib/presentation/names/name_list_screen.dart`, `app/lib/l10n/app_de.arb`
- Create: `app/lib/presentation/names/name_tile.dart`, `app/lib/presentation/common/sync_indicator.dart`
- Test: `app/test/presentation/names/name_list_screen_test.dart`, `app/test/presentation/common/sync_indicator_test.dart`

**Interfaces:**
- Consumes: `catalogProvider`, `syncStateProvider`, `Catalog.collectiveAccounts/personsByTier`.
- Produces: `NameListScreen` (approved variant B): header "Wer trinkt?"; a fixed top row "Sammelkonten" with collective accounts (accent `#9CC46A`); below, one column per tier side by side (column title = tier name, rail/accent colour = tier palette by index), names alphabetical in a grid. **Overflow:** start with 3 tiles per row per column at tile height 64; if the tallest column does not fit the available height, switch to 4 per row and height 52; if it still does not fit, each column scrolls independently (`ListView`/`GridView` with its own controller) and shows a bottom fade gradient; the collective row never scrolls. Tap on a name → `DrinkSelectionScreen(personId)` (Task 10). Empty catalog (no visible persons) → centred hint "Noch keine Personen angelegt – bitte im Admin-Bereich anlegen." `SyncIndicator` bottom-right: nothing when all synced; "n Buchungen warten" when queued > 0; "n Buchungen abgelehnt" when failed > 0; "Gerät nicht autorisiert" when unauthorised (takes precedence); small, muted, never a dialog.

- [ ] **Step 1: Failing tests** (1280×800 surface via `tester.view.physicalSize`/`devicePixelRatio = 1`):
  - shows collective row and one column per tier in tier order with the right names; hidden/inactive not shown.
  - 12 persons per tier → 3 per row, no scrolling.
  - 30 persons in one tier → 4 per row, no scrolling (find tile widths/positions).
  - 60 persons in one tier → column scrolls (`Scrollable` present; last name reachable via `scrollUntilVisible`), collective row stays at the same position.
  - tap on a name pushes the drink screen for that person id.
  - empty catalog hint.
  - sync indicator: table test over states → expected German text (or absent).
- [ ] **Step 2–4:** RED → implement → GREEN.
- [ ] **Step 5: Commit** `feat(app): add name list screen with overflow and sync indicator`

---

### Task 10: Drink selection, order bar, quantity sheet and booking

**Files:**
- Create: `app/lib/presentation/drinks/drink_selection_screen.dart`, `drink_tile.dart`, `order_bar.dart`, `quantity_sheet.dart`, `keypad.dart`, `order_controller.dart`
- Modify: `app/lib/l10n/app_de.arb`
- Test: `app/test/presentation/drinks/order_controller_test.dart`, `drink_selection_screen_test.dart`, `quantity_sheet_test.dart`

**Interfaces:**
- Consumes: `OrderDraft` (Task 3), `catalogProvider`, `runningTotalProvider`, `BookingRepository.addAll`, `SyncService.syncNow`, `clockProvider`, `uuid`.
- Produces:
  - `OrderController` (Riverpod `Notifier` family by personId, holding `OrderDraft`, `bool sheetOpenFor` drinkId?): `tap(drink)`, `setQuantity`, `discard()`, `commit()`, `openSheet/closeSheet`. **Auto-commit timer: 8 s after the last tap** (constant `kAutoBookDelay = Duration(seconds: 8)`), restarted by every tap and every quantity change, **paused while the quantity sheet is open** and restarted when it closes. `commit()` creates one `Booking` per line (`id` = UUID v4, `quantity`, the line's fixed `unitPriceCents`, `bookedAt = clock.now()`, status queued), writes them with `addAll`, fires `syncNow()` without awaiting (`unawaited`), and signals the screen to return to the name list. Commit on an empty draft does nothing.
  - Screen (approved layout): header with person name (large, Archivo wide), tier name, running total "seit der letzten Abrechnung"; button "Andere Person" (top-left) — **if the draft is not empty it books it first** (Review Focus 3; spec said "discards" — see ruling note below), then pops; one row per group (rail with group colour, group name, no price on the rail), drink tiles 7 per row (`minmax(0,1fr)` equivalent: equal widths), tile shows name, price for this person, counter badge bottom-right when quantity > 0 and accent fill in the group colour.
  - Order bar (visible when draft not empty): "2× Apfelschorle, 1× Augustiner Hell", total, countdown hint "wird in n Sekunden gebucht", buttons "Verwerfen" and "Fertig", a draining progress line.
  - Quantity sheet (opens on the 3rd tap of a drink): drink name, "Anzahl, je 1,15 €", −/+ buttons, large number field, in-app keypad 1–9, "Kasten (n)" (n = crate size), 0, ⌫; total of the whole order; buttons **"Weitere Getränke"** (close sheet, keep quantity) and **"Buchen"** (commit whole order). No discard button in the sheet. Keypad input replaces the number on first key press after opening, then appends; max 999; ⌫ to empty shows 0; quantity 0 + "Weitere Getränke" removes the line.
  - App lifecycle: `AppLifecycleListener` — on `paused`/`hidden` with a non-empty draft → `commit()` immediately (Review Focus 3).
  - After commit: SnackBar-free; the screen pops back to the name list (the name list may show a short confirmation banner "Gebucht: 2× Apfelschorle" for 3 s — implement as part of this task in `NameListScreen` via a returned result).

> **Ruling to confirm with the maintainer at plan review:** spec §4.2 says "Andere Person" discards the pending order. With multi-tap orders that silently loses drinks a member already tapped; this plan books instead. If the maintainer prefers discard, flip `kOtherPersonBooksPendingOrder` and the one test.

- [ ] **Step 1: Failing tests**
  - controller (with `fake_async` and fakes): tap → no commit before 8 s, commit at 8 s; second tap at 5 s → commit at 13 s; sheet open pauses (no commit at 30 s while open), closing restarts 8 s; `discard()` clears without writing; `commit()` writes one booking per line with fixed prices and UUIDs, calls `syncNow` once; empty commit writes nothing.
  - **RF4:** catalog price changes between tap and commit → booking has the tap-time price.
  - **RF3:** lifecycle `paused` with pending draft → booking written.
  - screen: groups and tiles rendered for the person's tier with correct prices; hidden/no-price drinks absent; tapping shows badge counts; 3rd tap opens sheet; keypad sets 24, "Kasten (20)" sets 20; "Weitere Getränke" keeps 24 and returns; "Buchen" writes the order and returns to the name list; "Verwerfen" clears the bar; header total updates after commit (via fakes).
  - "Andere Person" with pending draft books it, with empty draft just pops.
- [ ] **Step 2–4:** RED → implement → GREEN.
- [ ] **Step 5: Commit** `feat(app): add drink selection with multi-tap orders and auto-booking`

---

### Task 11: Kiosk behaviour and Android build

**Files:**
- Modify: `app/lib/main.dart`, `app/android/app/src/main/AndroidManifest.xml`, `app/android/app/build.gradle(.kts)`, `README.md`
- Test: `app/test/presentation/kiosk_test.dart`

**Interfaces:**
- Produces: `Future<void> configureKiosk(KioskPlatform p)` called from `main()` — locks orientation to landscape (`SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])`), immersive sticky UI mode, `WakelockPlus.enable()`; `KioskPlatform` is a small interface wrapping those three calls so the test verifies them with a fake. Android: `applicationId "dev.bartab.app"`, label "bar-tab", `INTERNET` permission, `android:usesCleartextTraffic="false"` (HTTPS only; local HTTP for development via a debug-only network security config allowing cleartext to `10.0.2.2` and `localhost`).
- README "Tablet" section: build (`flutter build apk --release` is the maintainer's step), sideload, first-start pairing, enabling Android screen pinning.

- [ ] **Step 1: Failing test** — `configureKiosk` calls the three platform operations with the right arguments.
- [ ] **Step 2–4:** RED → implement → GREEN; then `flutter build apk --debug` succeeds (paste the last lines).
- [ ] **Step 5: Commit** `feat(app): add kiosk mode and Android configuration`

---

### Task 12: End-to-end sync against the real server

**Files:**
- Create: `app/tool/e2e.sh`, `app/test_e2e/sync_against_server_test.dart`
- Modify: `README.md` (how to run e2e), `CLAUDE.md` (mention e2e)

**Interfaces:**
- `app/tool/e2e.sh`: builds and starts the server image (`docker compose -p bartab-e2e` with a throwaway generated `.env` in a temp dir, port 18080 published via a temp override, `seed-demo` executed), waits for `/api/v1/health`, runs `flutter test test_e2e --dart-define=E2E_BASE_URL=http://localhost:18080 --dart-define=E2E_DEVICE_KEY=<key>`, always tears down (`trap`) and deletes the temp files and volume.
- The test uses the real `BarTabApi`, real `SyncService`, in-memory Drift DB (no Flutter UI): fetch catalog (demo data visible, umlaut name intact), book 3 drinks for one person with the catalog prices, `syncNow()` → all accepted, tabs total equals the sum, running total equals the server tab and nothing is double-counted; run `syncNow()` again → no new POST of those ids (assert via server tabs unchanged); post a booking with a stale price → still accepted with that price (server never re-prices).
- Not part of `check.sh`/CI (needs Docker); run locally before merging the milestone.

- [ ] **Step 1: Write the e2e test** (it fails while the script/server is missing).
- [ ] **Step 2: Implement** `e2e.sh`; run it → PASS (paste output).
- [ ] **Step 3: Full** `app/tool/check.sh` and `server/tool/test.sh` → PASS.
- [ ] **Step 4: Commit** `test(app): add end-to-end sync test against the real server`
