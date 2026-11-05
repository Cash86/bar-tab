# Admin Storno Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The admin opens a PIN-protected admin area from a gear icon on the name list, sees the
open period's bookings (filter by person) and cancels wrong ones; cancelled bookings leave the
running totals and the quick-bar rankings (issue #3).

**Architecture:** The server replaces the fixed 15-minute signed admin token with an in-memory,
device-bound, sliding session store (5 min idle safety net, explicit logout). Bookings gain
`cancelled_at` / `cancelled_by_device_id` (Alembic 0002); two admin endpoints list and cancel.
The app gets admin API calls, a Riverpod admin-session controller (login, logout, throttled
keep-alive, 2-minute idle logout) and three plain screens: PIN gate, admin home, bookings list.
No Drift change: running totals already come from `/tabs`, so a storno plus `syncNow()` suffices.

**Tech Stack:** FastAPI + SQLAlchemy + Alembic (server), Flutter + Riverpod + freezed (app).

**Spec:** `docs/superpowers/specs/2026-11-02-bar-tab-design.md` — §4.1 (gear icon), §4.3 intro
and "Bookings", §5 "Auth", "Storno", "Drink rankings", §12 entries "Storno" and "Admin session".

## Global Constraints

- Repo English; every UI string via `app/lib/l10n/app_de.arb` (German). No hard-coded strings.
- TDD: failing test first, seen failing for the right reason. Never weaken existing tests.
  **Exception decided by the maintainer (2026-11-05):** the 900 s admin-token behaviour is
  replaced, so `test_token_expires_after_900_seconds_of_injected_clock` and the `expires_in == 900`
  assertion in `server/tests/api/test_admin_session.py` are rewritten to the sliding rules
  (Task 1). No other existing test changes meaning.
- No `datetime.now()` / `DateTime.now()` outside the clock wrapper; take a `Clock`.
- Every schema change ships a migration and a test: Alembic `0002` here; no Drift change.
- IDs UUID4 strings; timestamps UTC, timezone-aware; money integer cents.
- Server: `server/tool/test.sh` clean (pytest, ruff check, ruff format --check), line length 100.
  Layers: domain pure, persistence, api; dependencies point inward.
- App: `app/tool/check.sh` clean. Generated files not committed.
- `api/openapi.json` is regenerated with `server/tool/export_openapi.py` whenever routes or
  schemas change; `app/test/data/api/dto_contract_test.dart` covers every new DTO.
- Admin session: idle limit **300 s** server-side, sliding on every admin request; app idle
  logout **2 minutes** (`idleTimeoutProvider`); keep-alive ping at most once per **60 s**, only
  on user interaction. Sessions in memory; uvicorn stays single-worker.
- Error detail strings: `admin_session_required` (401), `booking_not_found` (404),
  `period_closed` (409), `already_cancelled` (409).
- Every query that sums or counts bookings filters `Booking.cancelled_at.is_(None)`. Stock and
  settlement queries do not exist yet (milestone 4); add this rule to the M4 carry-overs.
- Conventional Commits; every commit ends with a blank line and
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; reference `Refs #3`.

## Review Focus

1. **Admin works in the list for longer than 5 minutes, only scrolling and reading** — the
   session must not expire: interaction triggers the throttled keep-alive. Test in Task 5.
2. **Server restarted while the admin area is open** — the next admin call gets 401; the app
   drops the token and shows the PIN gate again, never a crash or a "device not authorised"
   state. Tests in Task 4 (client maps the detail) and Task 6 (gate reappears).
3. **Storno tapped twice quickly, or on two tablets** — exactly one storno; the second gets 409
   `already_cancelled` and the app just reloads the list. Tests in Task 3 and Task 7.
4. **Admin area left open and walked away from** — after 2 minutes the app logs out (server
   session revoked) and returns to the name list. Test in Task 6.
5. **Tablet offline when opening admin or cancelling** — a clear "Server nicht erreichbar" message,
   no token kept from a failed login, nothing changed locally. Tests in Task 6 and Task 7.

---

### Task 1: Server — sliding admin sessions and logout

**Files:**
- Modify: `server/bartab/security.py` (drop `ClockSigner`, `_signer`, `issue_admin_token`,
  `verify_admin_token`, `ADMIN_TOKEN_MAX_AGE`; add `AdminSessions`, `ADMIN_SESSION_IDLE_SECONDS`)
- Modify: `server/bartab/api/deps.py` (`require_admin`, add `get_admin_sessions`),
  `server/bartab/api/routes_admin_session.py`, `server/bartab/main.py`
  (`app.state.admin_sessions = AdminSessions(clock)`), `api/openapi.json`
- Test: `server/tests/api/test_admin_session.py`, `server/tests/api/test_openapi_shape.py`

**Interfaces:**
- Produces: `ADMIN_SESSION_IDLE_SECONDS = 300` and in `security.py`:
  ```python
  class AdminSessions:
      def __init__(self, clock: Clock, idle_seconds: int = ADMIN_SESSION_IDLE_SECONDS) -> None
      def open(self, device_id: str) -> str          # new token, secrets.token_urlsafe(32)
      def touch(self, token: str, device_id: str) -> bool  # valid+same device+not idle → extend
      def revoke(self, token: str, device_id: str) -> None  # no-op if unknown / other device
  ```
  Thread-safe with a `threading.Lock`; expired entries are removed on `touch`.
- Produces: `require_admin(...) -> str` now returns the device id (used by Task 3).
- Produces: `DELETE /api/v1/admin/session`, name `closeAdminSession`, device key required,
  `X-Admin-Token` header optional, always 204 (idempotent). `POST /admin/session` returns
  `expires_in = 300`.

- [ ] **Step 1: Rewrite/add tests** in `test_admin_session.py`:
  - `test_correct_pin_gives_token_that_opens_ping`: now asserts `body["expires_in"] == 300`.
  - Replace the 900 s test with `test_session_expires_after_300_idle_seconds`: login, advance
    299 s → ping 204; advance 301 s → 401 `admin_session_required`.
  - `test_each_admin_request_extends_the_session`: login; four times advance 250 s and ping →
    all 204 (1000 s in total).
  - `test_logout_revokes_the_session`: login, `DELETE SESSION` with token → 204; ping → 401.
  - `test_logout_is_idempotent_and_needs_device_key`: DELETE without token → 204; with garbage
    token → 204; without device key → 401 `invalid_device_key`.
  - `test_other_device_cannot_revoke`: device B DELETEs A's token → 204, A's ping still 204.
  - `test_sessions_do_not_survive_a_new_app`: token from one `create_app` is 401 on a second
    app built from the same settings (in-memory store).
  - Keep `test_token_is_bound_to_its_device` and `test_garbage_token_is_401` unchanged.
  - In `test_openapi_shape.py`: add `"closeAdminSession"` to `OPERATION_IDS`; assert the DELETE
    operation's security is `[{"deviceKey": [], "adminToken": []}]`.
- [ ] **Step 2: Run** `server/tool/test.sh tests/api/test_admin_session.py
  tests/api/test_openapi_shape.py` — expected FAIL (`expires_in` 900, no DELETE route).
- [ ] **Step 3: Implement** `AdminSessions`, wire it in `main.py`, make `require_admin` call
  `touch` and return `device_id`, add the DELETE route (reads the token via
  `admin_token_scheme`, calls `revoke`). Remove `itsdangerous` from `pyproject.toml` if no longer
  imported anywhere.
- [ ] **Step 4: Regenerate** `api/openapi.json`; run `server/tool/test.sh` — all green.
- [ ] **Step 5: Commit** `feat(server): keep admin sessions sliding with a 5 minute safety net`.

### Task 2: Server — storno columns, migration and repository

**Files:**
- Modify: `server/bartab/persistence/models.py` (`Booking.cancelled_at: Mapped[datetime | None]
  = mapped_column(UtcDateTime, nullable=True)`, `Booking.cancelled_by_device_id: Mapped[str |
  None]`)
- Create: `server/alembic/versions/0002_booking_storno.py` (`down_revision` = 0001's revision id;
  `batch_alter_table("bookings")` adding both nullable columns; downgrade drops them)
- Modify: `server/bartab/persistence/repos.py`
- Test: `server/tests/persistence/test_migrations.py`, `server/tests/persistence/test_repos.py`

**Interfaces:**
- Produces in `repos.py`:
  ```python
  class CancelOutcome(StrEnum): CANCELLED, NOT_FOUND, PERIOD_CLOSED, ALREADY_CANCELLED
  def open_period_bookings(session: Session, person_id: str | None = None) -> list[Booking]
      # open period only, cancelled included, ORDER BY booked_at DESC, id DESC
  def cancel_booking(session: Session, booking_id: str, device_id: str, clock: Clock
      ) -> tuple[CancelOutcome, Booking | None]
      # check order: not found → closed period → already cancelled → set cancelled_at=now,
      # cancelled_by_device_id, updated_at=now; flush
  ```
  `tabs_for_open_period` and `drink_rankings` filter `Booking.cancelled_at.is_(None)`; remove
  the `TODO(milestone 3)` comment.

- [ ] **Step 1: Write failing tests.** Migration: `test_models_match_migration` already guards
  the new columns (it fails until 0002 exists); add `test_downgrade_removes_storno_columns`
  (upgrade head, downgrade `-1`, `bookings` has no `cancelled_at`). Repos (use `db_session` and a
  `FixedClock`): `test_cancel_marks_booking_with_time_and_device`,
  `test_cancel_unknown_booking_is_not_found`, `test_cancel_twice_is_already_cancelled` (second
  call leaves the first `cancelled_at` unchanged), `test_cancel_in_closed_period_is_rejected`
  (set the booking's period `closed_at`, open a new period), `test_open_period_bookings_newest_first_and_filtered`
  (three bookings, two persons, one in a closed period → only open-period ones, newest
  `booked_at` first, `person_id` filter works, cancelled one still listed),
  `test_tabs_exclude_cancelled_bookings`, `test_rankings_exclude_cancelled_bookings`.
- [ ] **Step 2: Run** `server/tool/test.sh tests/persistence` — expected FAIL (missing
  attributes / functions).
- [ ] **Step 3: Implement** model columns, migration 0002, the repository functions and filters.
- [ ] **Step 4: Run** `server/tool/test.sh` — green, including `alembic upgrade head` on a fresh DB.
- [ ] **Step 5: Commit** `feat(server): record stornos on bookings`.

### Task 3: Server — admin booking endpoints

**Files:**
- Create: `server/bartab/api/routes_admin_bookings.py`
- Modify: `server/bartab/api/schemas.py`, `server/bartab/main.py`, `api/openapi.json`
- Test: `server/tests/api/test_admin_bookings.py`, `server/tests/api/test_openapi_shape.py`

**Interfaces:**
- Consumes: `require_admin -> str` (Task 1), `open_period_bookings`, `cancel_booking` (Task 2).
- Produces schemas:
  ```python
  class AdminBookingOut(BaseModel):
      id: str; person_id: str; drink_id: str; quantity: int; unit_price_cents: int
      booked_at: datetime; is_late: bool; cancelled_at: datetime | None
  class AdminBookingsResponse(BaseModel): bookings: list[AdminBookingOut]
  ```
  Datetimes returned timezone-aware UTC (SQLite gives naive values; reuse the `replace(tzinfo=UTC)`
  pattern from `get_tabs`).
- Produces routes (both `dependencies` on `require_admin`, 401 documented with `ErrorResponse`):
  - `GET /api/v1/admin/bookings?person_id=…` → `AdminBookingsResponse`, name `listAdminBookings`.
  - `POST /api/v1/admin/bookings/{booking_id}/cancel` → 200 `AdminBookingOut`, name
    `cancelBooking`; 404 `booking_not_found`, 409 `period_closed` / `already_cancelled`, both
    documented with `ErrorResponse`.

- [ ] **Step 1: Write failing tests** (seed like `tests/api/test_tabs.py`, log in with PIN
  `1234` for the admin header): `test_list_requires_admin_session` (device key only → 401
  `admin_session_required`), `test_list_returns_open_period_newest_first`,
  `test_list_filters_by_person`, `test_cancel_removes_booking_from_tabs` (book 2×250 for p-1,
  cancel → `/tabs` lacks p-1; list shows `cancelled_at == "2026-11-02T18:00:00Z"`),
  `test_cancel_removes_booking_from_rankings`, `test_cancel_twice_is_409_already_cancelled`,
  `test_cancel_unknown_is_404`, `test_cancel_in_closed_period_is_409_period_closed` (close the
  period directly via `app.state.session_factory`, set `closed_at`, `ensure_open_period`),
  `test_cancel_records_the_admin_device` (read the row: `cancelled_by_device_id ==
  device_id_for_key(DEVICE_KEYS[0])`), `test_reposting_a_cancelled_booking_stays_cancelled`
  (re-POST the same booking id → `duplicate`, still absent from `/tabs`). Shape test: add both
  operation ids; cancel documents 404 and 409.
- [ ] **Step 2: Run** `server/tool/test.sh tests/api` — expected FAIL (404 routes).
- [ ] **Step 3: Implement** schemas and routes; register the router in `main.py`.
- [ ] **Step 4: Regenerate** `api/openapi.json`; `server/tool/test.sh` — green.
- [ ] **Step 5: Commit** `feat(server): list and cancel bookings from the admin area`.

### Task 4: App — admin DTOs and API calls

**Files:**
- Modify: `app/lib/data/api/dto.dart`, `app/lib/data/api/api_client.dart`,
  `app/lib/data/api/mappers.dart`
- Create: `app/lib/domain/admin_booking.dart`
- Test: `app/test/data/api/dto_contract_test.dart`, `app/test/data/api/api_client_test.dart`,
  `app/test/data/api/mappers_test.dart`

**Interfaces:**
- Produces DTOs (freezed + json, snake_case like the existing ones): `AdminSessionRequestDto{pin}`,
  `AdminSessionResponseDto{token, expiresIn}`, `AdminBookingDto{id, personId, drinkId, quantity,
  unitPriceCents, bookedAt, isLate, cancelledAt?}`, `AdminBookingsDto{bookings}`.
- Produces domain (freezed): `AdminBooking{id, personId, drinkId, quantity, unitPriceCents,
  bookedAt, isLate, DateTime? cancelledAt}` with `int get amountCents => quantity *
  unitPriceCents` and `bool get isCancelled`; `AdminBooking adminBookingFromDto(AdminBookingDto)`.
- Produces in `api_client.dart`:
  ```dart
  sealed class AdminLogin {}  // AdminLoggedIn(String token) | AdminWrongPin() | AdminLockedOut(int retryAfter)
  final class AdminSessionEndedException extends ApiException  // 401 admin_session_required
  final class BookingNotCancellableException extends ApiException { final String reason; } // 404/409 detail
  Future<AdminLogin> openAdminSession(String pin);
  Future<void> closeAdminSession(String token);
  Future<void> pingAdmin(String token);
  Future<List<AdminBookingDto>> listAdminBookings(String token, {String? personId});
  Future<AdminBookingDto> cancelBooking(String token, String bookingId);
  ```
  Admin calls send `X-Admin-Token`. A 401 whose JSON `detail` is `admin_session_required` throws
  `AdminSessionEndedException`; any other 401 stays `UnauthorisedException`.

- [ ] **Step 1: Write failing tests.** Contract test: one `_Case` per new DTO, `cancelledAt`
  both null and set. Client tests with `FakeApiServer`: login 200 → `AdminLoggedIn('t')` and
  body `{"pin": "1234"}`; 401 `wrong_pin` → `AdminWrongPin`; 429 → `AdminLockedOut(60)`;
  `listAdminBookings('t', personId: 'p-1')` hits `admin/bookings?person_id=p-1` with header
  `X-Admin-Token: t`; 401 `admin_session_required` → `AdminSessionEndedException`; 401
  `invalid_device_key` → `UnauthorisedException`; cancel 409 `already_cancelled` →
  `BookingNotCancellableException` with that reason; `closeAdminSession` sends DELETE.
  Mapper test: `amountCents` and `isCancelled`.
- [ ] **Step 2: Run** `app/tool/check.sh` — expected FAIL (undefined classes).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `app/tool/check.sh` — green.
- [ ] **Step 5: Commit** `feat(app): talk to the admin endpoints`.

### Task 5: App — admin session controller

**Files:**
- Create: `app/lib/presentation/admin/admin_session.dart`
- Test: `app/test/presentation/admin/admin_session_test.dart`

**Interfaces:**
- Consumes: Task 4 API, `apiProvider`, `clockProvider`.
- Produces:
  ```dart
  const kAdminKeepAliveInterval = Duration(seconds: 60);
  enum AdminLoginResult { success, wrongPin, locked, unreachable }
  final adminSessionProvider = NotifierProvider<AdminSessionNotifier, String?>(...); // token or null
  class AdminSessionNotifier extends Notifier<String?> {
    Future<(AdminLoginResult, int? retryAfter)> login(String pin);
    Future<void> logout();      // state = null first, then best-effort closeAdminSession
    void onInteraction();       // pings if ≥ kAdminKeepAliveInterval since the last admin request
    Future<T> run<T>(Future<T> Function(BarTabApi api, String token) request);
        // records the request time; on AdminSessionEndedException sets state = null, rethrows
  }
  ```
  A ping that fails with `NetworkException` is logged and ignored; `AdminSessionEndedException`
  ends the session (state null).

- [ ] **Step 1: Write failing tests** (ProviderContainer + `FakeApiServer` + `FixedClock`):
  `login stores the token`; `wrong pin and lockout keep no token` (locked returns retryAfter 60);
  `offline login is unreachable`; `logout clears the token before the server answers and sends
  DELETE`; `logout while offline still clears the token`; `interaction pings at most once per 60
  s` (interactions at 0, 30, 61 s → exactly one ping, at 61 s); `a request resets the keep-alive
  clock`; `session ended on a call clears the token`; `session ended on a ping clears the token`.
- [ ] **Step 2: Run** `app/tool/check.sh` — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `app/tool/check.sh` — green.
- [ ] **Step 5: Commit** `feat(app): keep the admin session alive while the admin works`.

### Task 6: App — gear icon, PIN gate, admin home, idle logout

**Files:**
- Create: `app/lib/presentation/admin/admin_gate.dart` (PIN prompt when no token, otherwise the
  admin home with "Buchungen" and "Abmelden"), `app/lib/presentation/admin/admin_idle.dart`
  (`AdminIdleGuard` widget: `Listener` on pointer down/move → `onInteraction()` and re-arm a
  timer of `idleTimeoutProvider`; on expiry → `logout()` and
  `Navigator.popUntil(route.isFirst)`)
- Modify: `app/lib/presentation/names/name_list_screen.dart` (gear `IconButton`,
  `Key('admin-gear')`, at the right end of the title row; pushes `AdminGate`),
  `app/lib/l10n/app_de.arb`
- Test: `app/test/presentation/admin/admin_gate_test.dart`,
  `app/test/presentation/names/name_list_screen_test.dart`

**Interfaces:**
- Consumes: `adminSessionProvider` (Task 5), `Keypad` with `crateLabel: null`.
- Produces: `class AdminGate extends ConsumerWidget`; every admin route is wrapped in
  `AdminIdleGuard`; the "Buchungen" button (`Key('admin-bookings')`) pushes
  `AdminBookingsScreen` (Task 7).
- Strings (German): `adminTitle` "Admin", `adminPinTitle` "Admin-PIN", `adminPinLogin`
  "Anmelden", `adminPinWrong` "PIN falsch", `adminPinLocked` "Gesperrt – noch {seconds} s",
  `adminUnreachable` "Server nicht erreichbar", `adminBookings` "Buchungen", `adminLogout`
  "Abmelden". PIN digits shown masked (•), 4–8 digits, "Anmelden" disabled below 4.

- [ ] **Step 1: Write failing tests:** tapping the gear opens the PIN prompt; correct PIN shows
  the admin home; wrong PIN shows "PIN falsch" and clears the input; 429 shows the lockout
  seconds; offline shows "Server nicht erreichbar"; more than 8 digits are ignored; "Abmelden"
  returns to the name list and sends DELETE; 2 minutes without touch (override
  `idleTimeoutProvider` short) logs out and returns to the name list; touches keep it open;
  token cleared (session ended) while on the admin home → PIN prompt is shown again.
- [ ] **Step 2: Run** `app/tool/check.sh` — expected FAIL.
- [ ] **Step 3: Implement** (plain Material widgets, existing theme colours; no design work).
- [ ] **Step 4: Run** `app/tool/check.sh` — green.
- [ ] **Step 5: Commit** `feat(app): enter the admin area with the PIN`.

### Task 7: App — bookings list and storno

**Files:**
- Create: `app/lib/presentation/admin/admin_bookings_screen.dart`
- Modify: `app/lib/l10n/app_de.arb`
- Test: `app/test/presentation/admin/admin_bookings_screen_test.dart`

**Interfaces:**
- Consumes: `adminSessionProvider.notifier.run(...)`, `listAdminBookings`, `cancelBooking`,
  `adminBookingFromDto`, `catalogProvider` (person and drink names; all persons incl. hidden and
  inactive in the filter, sorted by name), `syncServiceProvider` (`syncNow()` after a storno),
  `formatCents` from `presentation/format.dart` (add a date helper there if needed).
- Produces: `class AdminBookingsScreen extends ConsumerStatefulWidget`. Row: time
  (`dd.MM. HH:mm`, local), person, drink, `{qty}×`, unit price, amount; late bookings marked;
  cancelled rows greyed with "storniert" and no storno button. Storno button
  `Key('storno-<id>')` → Material `AlertDialog` ("Buchung stornieren?" with the row summary,
  "Abbrechen" / "Stornieren"); while a storno runs its button is disabled.
- Strings: `adminBookingsEmpty` "Keine Buchungen in dieser Periode", `adminFilterAll` "Alle
  Personen", `adminStorno` "Stornieren", `adminStornoConfirm` "Buchung stornieren?",
  `adminCancel` "Abbrechen", `adminStornoDone` "Storniert", `adminCancelled` "storniert",
  `adminLate` "verspätet", `adminStornoFailed` "Storno nicht möglich".

- [ ] **Step 1: Write failing tests:** list shows names, amounts, newest first as delivered;
  picking a person reloads with `person_id`; cancelled row greyed without button; storno →
  confirm → POST cancel, row shows "storniert", `syncNow` ran (a GET `tabs` request follows);
  "Abbrechen" sends nothing; double tap on "Stornieren" sends one POST; 409 `already_cancelled`
  reloads the list and shows "Storno nicht möglich"; offline storno shows "Server nicht
  erreichbar" and leaves the row unchanged; 401 `admin_session_required` returns to the PIN
  prompt.
- [ ] **Step 2: Run** `app/tool/check.sh` — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `app/tool/check.sh` — green.
- [ ] **Step 5: Commit** `feat(app): cancel bookings from the admin area`.

### Task 8: End to end, docs and carry-overs

**Files:**
- Modify: `app/test_e2e/sync_against_server_test.dart`, `app/tool/e2e.sh` (pass
  `--dart-define=E2E_ADMIN_PIN=4711`)
- Modify: `docs/superpowers/specs/2026-11-02-bar-tab-design.md` only if something built differs

**Interfaces:** Consumes everything above.

- [ ] **Step 1: Write the e2e test** `storno removes a booking from the tab`: book 2 units for a
  demo person and sync; login with the PIN; `listAdminBookings` contains it; cancel it; sync →
  running total back to the value before; cancel again → `BookingNotCancellableException`
  (`already_cancelled`); logout → `pingAdmin` throws `AdminSessionEndedException`.
- [ ] **Step 2: Run** `app/tool/e2e.sh` — green (needs Docker).
- [ ] **Step 3: Full checks:** `server/tool/test.sh` and `app/tool/check.sh` — both clean.
- [ ] **Step 4: Commit** `test(app): check storno against the real server`.
- [ ] **Step 5:** Note on issue #3 what was built; keep the issue open until the tablet check
  (maintainer's plan: test everything on the tablet at the end). Record the M4 carry-over
  "stock/settlement/monthly queries must exclude cancelled bookings; storno section in PDF".
