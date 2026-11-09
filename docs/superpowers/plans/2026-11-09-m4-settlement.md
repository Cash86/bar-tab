# M4 Settlement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inventory & settlement (with an opening count for the cut-over), settlement PDF mailed to
a recipient list, shrinkage valued in euros, and a monthly interim mail with an overdue notice.

**Architecture:** One pure domain computation (`bartab/domain/settlement.py`) produces every figure;
the review endpoint, the close snapshot, the PDF and the mails all render from it. The server closes
a period atomically, stores a JSON snapshot of the figures, then mails. A scheduler task in the
FastAPI lifespan sends the monthly mail. The app adds three admin screens (inventory flow, opening
count, settings) and keeps the count as a local draft in the existing `AppConfig` key-value table.

**Tech Stack:** FastAPI, SQLAlchemy, Alembic, `fpdf2` (new, pure Python), `smtplib`; Flutter,
Riverpod, freezed/json_serializable, Drift (existing tables only), mocktail.

**Spec:** `docs/superpowers/specs/2026-11-09-m4-settlement-design.md` (with main spec
`2026-11-02-bar-tab-design.md` §4.4, §5).

## Global Constraints

- Money is integer cents; no floats anywhere, also not in the PDF (format cents → `1,50 €`).
- No `datetime.now()`/`DateTime.now()`; use `Clock`. Local times use `BARTAB_TZ`.
- `bartab/domain` stays pure. New modules: `bartab/reports/` (PDF + mail text, depends only on
  domain) and `bartab/mail.py` (SMTP, I/O).
- Every stock/settlement/monthly figure excludes `bookings.cancelled_at IS NOT NULL` and
  `stock_entries.cancelled_at IS NOT NULL`.
- Schema change → Alembic `0004` + migration test (`alembic upgrade head` on a fresh DB).
- API change → run `server/tool/export_openapi.py`, commit `api/openapi.json`; app DTOs get
  `dto_contract_test.dart` cases.
- UI strings only in `app/lib/l10n/app_de.arb`; admin screens are pushed with `adminRoute`
  (standard look).
- Server: `server/tool/test.sh` clean; app: `app/tool/check.sh` clean; before merge
  `app/tool/e2e.sh`.
- Conventional Commits, each ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A second tablet syncs a booking (or someone cancels one) between review and confirm → confirm
   answers 409 `stale_review`, nothing closes (Task 3 test `test_close_with_stale_token_is_409`).
2. Confirm is sent twice (lost answer, retry) → exactly one closed period, same result (Task 3
   test `test_close_retry_with_same_token_is_idempotent`).
3. SMTP down at close → period closed, `mail_status == "failed"`, re-send works later (Task 6
   test `test_close_with_failing_mail_still_closes`).
4. Server restarts on the 1st after a successful send → no second mail; restart before the send
   → mail still goes out the same month (Task 7 tests).
5. Tablet idles out mid-count → counts are back after re-login (Task 10 test
   `draft survives leaving and re-entering the flow`).

---

### Task 1: Settlement domain computation

**Files:**
- Create: `server/bartab/domain/settlement.py`
- Test: `server/tests/domain/test_settlement.py`

**Interfaces:**
- Consumes: `bartab.domain.stock.DrinkStock` (reuse for expected/shrinkage).
- Produces (all frozen dataclasses):
  - `PersonIn(id, name, tier_id, is_hidden, is_collective)`, `TierIn(id, name, sort_order,
    is_active)`, `DrinkIn(id, name, group_id, group_name, crate_size, is_active)`,
    `BookingIn(person_id, drink_id, quantity, unit_price_cents, booked_at, cancelled_at,
    is_late)`, `StockIn(drink_id, kind, quantity, created_at, cancelled_at)` (kind ∈ opening/delivery).
  - `PersonLine(person_id, name, tier_id, quantities_by_group: dict[str,int], amount_cents)`
  - `DrinkLine(drink_id, name, group_id, opening, delivered, booked, expected, counted,
    shrinkage, value_cents, has_price: bool)`
  - `Settlement(period_id, started_at, ended_at, valuation_tier_id, valuation_tier_name,
    persons: list[PersonLine], hidden: list[PersonLine], drinks: list[DrinkLine],
    group_totals: dict[str, DrinkLine], persons_total_cents, hidden_total_cents,
    grand_total_cents, shrinkage_total_cents, deliveries: list[StockIn],
    cancelled_deliveries: list[StockIn], cancelled_bookings: list[BookingIn],
    person_drink: dict[str, dict[str, int]])`
  - `effective_valuation_tier(tiers, chosen_id: str | None) -> TierIn` — chosen if active, else
    active tier with lowest `sort_order`.
  - `drinks_to_count(drinks, stocks, bookings) -> list[DrinkIn]` — active drinks plus inactive
    ones whose expected stock ≠ 0.
  - `compute_settlement(*, period_id, started_at, ended_at, persons, tiers, drinks, bookings,
    stocks, prices: dict[tuple[str,str], int], counts: dict[str, int] | None,
    valuation_tier: TierIn) -> Settlement` — `counts=None` gives a preview without counts
    (counted/shrinkage `None`, value 0), used by the monthly mail.
  - `figures_token(s: Settlement) -> str` — sha256 hex of canonical JSON (`sort_keys=True`) of
    the settlement figures incl. counts and period id.
  - `settlement_to_json(s) -> dict` / `settlement_from_json(d) -> Settlement` (snapshot).

- [ ] **Step 1: Write the failing tests** (`test_settlement.py`), each with invented data:
  - `test_amount_is_sum_of_quantity_times_frozen_unit_price` – 2×150 + 1×170 → 470.
  - `test_cancelled_bookings_and_deliveries_are_excluded` – cancelled booking not in amount nor
    booked; cancelled delivery not in delivered; cancelled booking listed in
    `cancelled_bookings`.
  - `test_shrinkage_value_uses_valuation_tier_price` – expected 20, counted 17, Aktive price 60
    → shrinkage 3, value 180.
  - `test_negative_shrinkage_offsets_total` – drink A +3×60, drink B −1×100 → total 80.
  - `test_drink_without_valuation_price_counts_zero_and_is_flagged` – `has_price is False`,
    value 0.
  - `test_hidden_persons_are_separate_and_totals_split` – persons_total, hidden_total,
    grand_total = sum of both.
  - `test_persons_without_bookings_are_not_listed`; `test_deactivated_person_listed_in_tier`.
  - `test_effective_valuation_tier_falls_back_to_lowest_active_sort_order`.
  - `test_drinks_to_count_includes_inactive_with_stock_only`.
  - `test_token_changes_when_a_booking_or_count_changes` and `test_token_is_stable`.
  - `test_snapshot_round_trip` – `settlement_from_json(settlement_to_json(s)) == s`.

- [ ] **Step 2: Run** `server/tool/test.sh tests/domain/test_settlement.py` → FAIL (module
  missing).
- [ ] **Step 3: Implement** the interfaces above. Persons sorted by tier `sort_order`, then name;
  drinks by group then drink order as given by the caller.
- [ ] **Step 4: Run** the same command → PASS.
- [ ] **Step 5: Commit** `feat(server): compute settlement figures and shrinkage value`.

### Task 2: Monthly report schedule and overdue rule

**Files:**
- Create: `server/bartab/domain/monthly_report.py`
- Test: `server/tests/domain/test_monthly_report.py`

**Interfaces:**
- Produces:
  - `due_month(now_local: datetime, day: int, time_hhmm: str, sent_month: str | None) -> str |
    None` – returns `"YYYY-MM"` of the current month if `now_local` ≥ that month's `day` at
    `time_hhmm` and `sent_month != that`, else `None`. (Only the current month; no catch-up.)
  - `should_attempt(now: datetime, last_attempt_at: datetime | None) -> bool` – `True` if never
    attempted or ≥ 1 h since the last attempt (`RETRY_INTERVAL = timedelta(hours=1)`).
  - `overdue_days(today: date, last_inventory: date) -> int | None` – `None` while `today <=
    last_inventory + 1 calendar month` (clamped to month end, e.g. 31 Jan → 28/29 Feb), else
    the days since that date.

- [ ] **Step 1: Failing tests:** `test_not_due_before_day_and_time`, `test_due_at_time`,
  `test_not_due_when_sent_this_month`, `test_due_later_in_month_after_missed_time`,
  `test_retry_after_one_hour_only`, `test_overdue_none_within_one_month`,
  `test_overdue_counts_days_after_one_month` (last 2026-10-01, today 2026-11-11 → 10),
  `test_overdue_month_end_clamp` (2026-01-31 → due from 2026-02-28).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(server): schedule the monthly report and detect overdue inventory`.

### Task 3: Persistence – snapshot table, review, close, opening count, settings

**Files:**
- Create: `server/alembic/versions/0004_settlements.py`,
  `server/bartab/persistence/settlement.py`
- Modify: `server/bartab/persistence/models.py` (add `Settlement` model)
- Test: `server/tests/persistence/test_settlement_repo.py`,
  `server/tests/persistence/test_migrations.py` (add 0004 case)

**Interfaces:**
- Model `Settlement` table `settlements`: `id` (UUID4), `period_id` FK unique, `token` unique,
  `figures_json` TEXT, `mail_status` TEXT CHECK in (`pending`,`sent`,`failed`,`skipped`),
  `mail_error` nullable, `mailed_at` nullable, timestamps.
- `app_settings` keys: `mail_recipients` (JSON list), `valuation_tier_id`,
  `monthly_report_sent_month`, `monthly_report_last_attempt_at` (ISO UTC).
- Produces in `persistence/settlement.py`:
  - `class StaleReview(Exception)`, `class AlreadySettled(Exception)`,
    `class UnknownDrink(Exception)`, `class MissingCount(Exception)`.
  - `stock_overview(session) -> tuple[bool, list[tuple[DrinkIn, int]]]` – (opening count
    allowed = no closed period exists, drinks to count with expected stock).
  - `review(session, clock, counts: dict[str,int]) -> Settlement` – every drink of
    `drinks_to_count` must have a count (`MissingCount`), unknown ids → `UnknownDrink`.
  - `close(session, clock, token: str, counts) -> tuple[SettlementRow, bool]` – in one
    transaction (`BEGIN IMMEDIATE`, as existing writes): if a row with `token` exists → return
    it, `False` (idempotent); recompute, token mismatch → `StaleReview`; else store `count`
    entries for the period, close period (`closed_at = clock.now()`), open the next period with
    `started_at` = same instant and `opening` entries = counts, insert the snapshot row with
    `mail_status="pending"`, return it, `True`.
  - `record_opening_count(session, clock, counts)` – `AlreadySettled` if any closed period;
    cancels earlier non-cancelled `opening` entries of the open period (sets `cancelled_at`) and
    inserts new ones.
  - `last_inventory_at(session) -> datetime` – start of the open period if a closed period
    exists; else latest non-cancelled opening entry `created_at`; else open period start.
  - `last_settlement(session) -> SettlementRow | None`;
    `set_mail_status(session, row_id, status, error, clock)`.
  - `get_recipients(session) -> list[str]`, `set_recipients(session, list[str])`,
    `get_valuation_tier_id(session) -> str | None`, `set_valuation_tier_id(session, id)`.

- [ ] **Step 1: Failing tests:** migration test for 0004 (fresh DB upgrade head has
  `settlements`); repo tests `test_review_requires_every_drink_counted`,
  `test_close_stores_counts_and_opens_next_period_with_counts_as_opening`,
  `test_close_with_stale_token_is_409` (named so; raises `StaleReview`, no period closed),
  `test_close_retry_with_same_token_is_idempotent`,
  `test_snapshot_unchanged_after_price_change`,
  `test_late_booking_after_close_lands_in_new_period_marked_late`,
  `test_opening_count_replaces_previous_and_is_refused_after_a_settlement`,
  `test_last_inventory_at_rules` (three cases),
  `test_recipients_and_valuation_tier_round_trip`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (load inputs from DB, convert to domain
  dataclasses, call Task 1). **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(server): close a period with a figures snapshot and record opening
  counts`.

### Task 4: Settlement PDF and mail texts

**Files:**
- Modify: `server/pyproject.toml` (add `fpdf2==2.8.1` to dependencies)
- Create: `server/bartab/reports/__init__.py`, `server/bartab/reports/money.py`,
  `server/bartab/reports/settlement_pdf.py`, `server/bartab/reports/texts.py`
- Test: `server/tests/reports/test_settlement_pdf.py`, `server/tests/reports/test_texts.py`

**Interfaces:**
- `format_cents(cents: int) -> str` – `150 → "1,50 €"`, `-80 → "−0,80 €"`, `0 → "0,00 €"`.
- `render_settlement_pdf(s: Settlement, tz: str) -> bytes` – sections in this order: header
  (period from–to local, valuation tier name), per tier person table (quantity per group,
  amount), hidden accounts, totals (Mitglieder / versteckte Konten / Gesamt), shrinkage table
  per drink + group subtotals + total value (drinks without price marked "kein Preis"),
  deliveries, stornos, appendix person × drink. Use a bundled TTF with umlaut support (DejaVu
  Sans shipped by fpdf2 is not bundled → add `server/bartab/reports/fonts/DejaVuSans*.ttf`,
  licence file alongside).
- `settlement_mail(s, tz) -> tuple[str, str]` – subject `"bar-tab: Abrechnung {dd.mm.yyyy} –
  {dd.mm.yyyy}"`, short body with the three totals and shrinkage total.
- `monthly_mail(preview: Settlement, tz, overdue: int | None, month_label: str) -> tuple[str,
  str]` – subject `"bar-tab: Zwischenstand {Monat yyyy}"`; body starts with
  `"Inventur überfällig seit {X} Tagen"` when `overdue` is set; then
  `"Zwischenstand, keine Abrechnung"`, consumption per person and drink, amount per person so far,
  expected stock per drink.

- [ ] **Step 1: Failing tests:** `test_format_cents`; `test_pdf_contains_totals_and_umlauts`
  (render a snapshot with the person "Jörg Beispiel", extract text with `pypdf==5.1.0`, added to
  the dev dependencies, and assert the name and the grand total appear);
  `test_pdf_marks_drink_without_price`, `test_settlement_mail_subject_and_totals`,
  `test_monthly_mail_overdue_line_first`, `test_monthly_mail_without_overdue_line`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS (Docker image rebuilt
  by `test.sh`).
- [ ] **Step 5: Commit** `feat(server): render the settlement PDF and the mail texts`.

### Task 5: Mailer

**Files:**
- Create: `server/bartab/mail.py`
- Test: `server/tests/test_mail.py`

**Interfaces:**
- `class Mailer(Protocol): def send(self, to: list[str], subject: str, body: str,
  attachment: tuple[str, bytes] | None = None) -> None` (raises `MailError` on failure).
- `class MailError(Exception)`, `class MailNotConfigured(MailError)`.
- `class SmtpMailer` built from `Settings`: port 465 → `smtplib.SMTP_SSL`, else `SMTP` +
  `starttls()`; login when user set; timeout 20 s. Missing host/from → `MailNotConfigured`.
- `class FakeMailer` in `tests/fakes.py` (records sends, can be set to fail) — test-only.
- `app.state.mailer` set in `create_app(settings, clock, mailer: Mailer | None = None)`;
  default `SmtpMailer(settings)`.

- [ ] **Step 1: Failing tests** with a patched `smtplib` (monkeypatch classes):
  `test_ssl_on_465`, `test_starttls_otherwise`, `test_attachment_is_pdf`,
  `test_not_configured_raises`, `test_smtp_error_becomes_mail_error`.
- [ ] **Step 2–4:** run FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(server): send mail via SMTP`.

### Task 6: Admin API – stock, review, close, opening count, settings, re-send

**Files:**
- Create: `server/bartab/api/routes_admin_settlement.py`,
  `server/bartab/api/routes_admin_settings.py`
- Modify: `server/bartab/api/schemas.py`, `server/bartab/main.py`, `api/openapi.json`
- Test: `server/tests/api/test_admin_settlement.py`, `server/tests/api/test_admin_settings.py`

**Interfaces (all `require_admin`, error bodies `{"detail": code}`):**
- `GET /admin/stock` (`getStock`) → `{opening_count_allowed: bool, drinks: [{drink_id, name,
  group_id, group_name, crate_size, expected}]}`.
- `POST /admin/settlement/review` (`reviewSettlement`) body `{counts: [{drink_id, quantity}]}` →
  `SettlementReviewOut {token, valuation_tier_name, drinks: [DrinkLineOut], groups:
  [GroupLineOut], persons_total_cents, hidden_total_cents, grand_total_cents,
  shrinkage_total_cents}`; 422 `missing_count` / `unknown_reference` / `invalid_quantity`
  (quantity 0..99999).
- `POST /admin/settlement/close` (`closeSettlement`) body `{token, counts}` → 201 (first) or
  200 (replay) `{period_id, closed_at, mail_status}`; 409 `stale_review`. After commit the route
  renders PDF + mail from the snapshot and sends to the recipients (`skipped` when no recipients
  or `MailNotConfigured`, `failed` with error on `MailError`), via `run_in_threadpool`.
- `POST /admin/opening-count` (`recordOpeningCount`) body `{counts}` → 204; 409
  `already_settled`.
- `GET /admin/settings` (`getSettings`) → `{recipients: [str], valuation_tier_id: str | null,
  effective_valuation_tier_id: str, last_settlement: {period_id, closed_at, mail_status} | null}`.
- `PUT /admin/settings/recipients` (`setRecipients`) `{recipients: [str]}` → 204; 422
  `invalid_email` (must match `^[^@\s]+@[^@\s]+\.[^@\s]+$`), duplicates removed, order kept.
- `PUT /admin/settings/valuation-tier` (`setValuationTier`) `{tier_id}` → 204; 422
  `unknown_reference` (unknown or inactive tier).
- `POST /admin/settlement/resend` (`resendSettlement`) → `{mail_status}`; 404 `no_settlement`.

- [ ] **Step 1: Failing tests** (FakeMailer injected): stock lists inactive drink with stock;
  review totals; `test_close_with_failing_mail_still_closes`; close sends PDF attachment named
  `abrechnung-YYYY-MM-DD.pdf` to all recipients; replay returns 200 and sends no second mail;
  stale token 409; opening count 204 then 409 after a close; settings validation; resend after a
  failure sets `sent`; every route 401 without admin session; `test_openapi_contract` updated by
  `server/tool/export_openapi.py`.
- [ ] **Step 2–4:** FAIL → implement → PASS (`server/tool/test.sh`).
- [ ] **Step 5: Commit** `feat(server): admin API for inventory, settlement and settings`.

### Task 7: Monthly report scheduler

**Files:**
- Create: `server/bartab/scheduler.py`
- Modify: `server/bartab/main.py` (lifespan starts/stops the task)
- Test: `server/tests/test_scheduler.py`

**Interfaces:**
- `run_monthly_report_once(session_factory, settings, clock, mailer) -> bool` – reads
  `monthly_report_sent_month` / `monthly_report_last_attempt_at`; if `due_month` and
  `should_attempt`: records the attempt, builds the preview (`compute_settlement(counts=None)`),
  overdue from `last_inventory_at`, sends to recipients; on success stores the sent month.
  Without recipients or SMTP: records the attempt only. Returns whether a mail was sent.
- `async def monthly_report_loop(...)` – calls the above via `asyncio.to_thread` every 60 s;
  exceptions are logged, never end the loop. Started in lifespan with `asyncio.create_task`,
  cancelled on shutdown. `create_app(..., start_scheduler: bool = True)`; tests pass `False`.

- [ ] **Step 1: Failing tests** with `FixedClock` + FakeMailer: sends once at the 1st 08:00
  local; `test_restart_after_send_does_not_resend` (new call with fresh state from DB → no
  send); `test_missed_time_sends_later_same_month`; `test_failure_retries_after_an_hour`;
  `test_mail_includes_overdue_line`; `test_no_recipients_records_attempt_only`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(server): send the monthly interim report`.

### Task 8: App API client and DTOs

**Files:**
- Modify: `app/lib/data/api/dto.dart`, `app/lib/data/api/api_client.dart`
- Test: `app/test/data/api/api_client_test.dart`, `app/test/data/api/dto_contract_test.dart`

**Interfaces (ApiClient, all take the admin `token` first like existing admin calls):**
- `Future<StockDto> getStock(String token)`;
  `Future<SettlementReviewDto> reviewSettlement(String token, Map<String,int> counts)`;
  `Future<SettlementCloseDto> closeSettlement(String token, String reviewToken,
  Map<String,int> counts)`; `Future<void> recordOpeningCount(String token, Map<String,int>
  counts)`; `Future<SettingsDto> getSettings(String token)`;
  `Future<void> setRecipients(String token, List<String> recipients)`;
  `Future<void> setValuationTier(String token, String tierId)`;
  `Future<MailStatus> resendSettlement(String token)`.
- `enum MailStatus { pending, sent, failed, skipped }`.
- 409 `stale_review` → `StaleReviewException`; 409 `already_settled` →
  `AlreadySettledException`; 422 `invalid_email` → `InvalidEmailException` (alongside the
  existing exception types).

- [ ] **Step 1: Failing tests:** one request/response test per method (path, method, body),
  error mapping tests, DTO contract cases for every new DTO against `api/openapi.json`.
- [ ] **Step 2–4:** `flutter test test/data/api` FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(app): API client for inventory, settlement and settings`.

### Task 9: Flush before settlement

**Files:**
- Modify: `app/lib/domain/repositories.dart`, `app/lib/data/repositories/booking_repository_impl.dart`,
  `app/lib/data/sync/sync_service.dart`
- Test: `app/test/data/repositories/booking_repository_test.dart`,
  `app/test/data/sync/sync_service_test.dart`

**Interfaces:**
- `BookingRepository.releaseHolds()` – sets `holdUntil = null` on all queued held bookings.
- `SyncService.flushForSettlement() -> Future<FlushResult>` with
  `FlushResult({required bool reachable, required int pending, required int failed})`: releases
  holds, runs one sync, then reads counts. Settlement may start only if `reachable && pending ==
  0`.

- [ ] **Step 1: Failing tests:** held booking is pushed by `flushForSettlement`; offline →
  `reachable: false`; failed (rejected/conflict) bookings are counted in `failed` but not in
  `pending`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(app): flush queued and held bookings before a settlement`.

### Task 10: Count draft

**Files:**
- Create: `app/lib/presentation/admin/count_draft.dart`
- Modify: `app/lib/presentation/admin/quantity_list.dart` (`QuantityLines` gains
  `Map<String, dynamic> toJson()` and `void restore(Map<String, dynamic>)` for crates/units)
- Test: `app/test/presentation/admin/count_draft_test.dart`,
  `app/test/presentation/admin/quantity_list_test.dart`

**Interfaces:**
- `enum CountMode { settlement, opening }`.
- `class CountDraftStore { CountDraftStore(ConfigStore store); Future<Map<String,dynamic>?>
  load(CountMode mode); Future<void> save(CountMode mode, Map<String,dynamic> lines); Future<void>
  clear(CountMode mode); }` – keys `count_draft_settlement`, `count_draft_opening` in
  `AppConfig` (no Drift schema change).
- Provider `countDraftStoreProvider` in `providers.dart`.

- [ ] **Step 1: Failing tests:** `QuantityLines` round trip; store save/load/clear per mode;
  corrupt JSON loads as `null`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(app): keep inventory counts as a local draft`.

### Task 11: Inventory & settlement flow and opening count screens

**Files:**
- Create: `app/lib/presentation/admin/inventory_screen.dart` (count step, shared by both modes),
  `app/lib/presentation/admin/settlement_review_screen.dart`
- Modify: `app/lib/presentation/admin/admin_home.dart` (tiles `settlement`, `opening`),
  `app/lib/l10n/app_de.arb`
- Test: `app/test/presentation/admin/inventory_screen_test.dart`,
  `app/test/presentation/admin/settlement_review_screen_test.dart`

**Behaviour:**
- Tile `settlement` "Inventur & Abrechnung" / "zählen, prüfen, abschließen"; tile `opening`
  "Anfangsbestand" / "nur vor der ersten Abrechnung".
- Settlement start: `flushForSettlement`; unreachable → "Server nicht erreichbar"; pending > 0 →
  "{n} Buchungen noch nicht gesendet – Abrechnung nicht möglich"; failed > 0 → warning
  "{n} fehlgeschlagene Buchungen werden nicht abgerechnet" (flow continues).
- Count step: `GET /admin/stock` list via `QuantityList` (crates + units); a draft exists →
  restored with the note "Entwurf fortgesetzt"; every change saves the draft; "Verwerfen" clears
  it (confirm dialog). "Prüfen" is enabled only when every listed drink has a count (an entered
  0 counts; untouched does not) → review.
- Opening mode: `opening_count_allowed == false` → "Anfangsbestand nur vor der ersten
  Abrechnung möglich" and no list; "Speichern" → `recordOpeningCount`, clears draft, back to
  admin home with "Anfangsbestand gespeichert".
- Review: table per drink (erwartet / gezählt / Schwund / Wert, "kein Preis" marker), group
  subtotals, totals (Mitglieder, versteckte Konten, Gesamt, Schwund gesamt "bewertet mit
  {tier}"); "Zurück" keeps counts; "Abrechnung abschließen" → confirm dialog → close.
  `StaleReviewException` → reload review + "Daten haben sich geändert – bitte erneut prüfen".
  Success → clear draft, message by `mail_status`: sent "Abgeschlossen, PDF verschickt"; failed
  "Abgeschlossen – Mail fehlgeschlagen, in Einstellungen erneut senden"; skipped
  "Abgeschlossen – keine Mail (keine Empfänger oder kein Mailserver)".

- [ ] **Step 1: Failing widget tests** for each bullet above (fake API via the existing
  `FakeApiServer`), including `draft survives leaving and re-entering the flow` (enter counts,
  idle logout, log in again, open tile → counts restored).
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(app): inventory, settlement and opening count flow`.

### Task 12: Settings screen

**Files:**
- Create: `app/lib/presentation/admin/settings_screen.dart`
- Modify: `admin_home.dart` (tile `settings` "Einstellungen" / "Mail-Empfänger, Schwund, PDF"),
  `app_de.arb`
- Test: `app/test/presentation/admin/settings_screen_test.dart`

**Behaviour:** recipient list with add (text field + "Hinzufügen", invalid → "Ungültige
E-Mail-Adresse") and remove per row, each change saved with `setRecipients`; dropdown
"Schwund bewerten mit" over active tiers (`setValuationTier`); section "Letzte Abrechnung" with
date and mail status text and "PDF erneut senden" (`resendSettlement`), hidden when there is no
settlement.

- [ ] **Step 1: Failing widget tests** for add/remove/invalid/dropdown/resend/no-settlement.
- [ ] **Step 2–4:** FAIL → implement → PASS (`app/tool/check.sh`).
- [ ] **Step 5: Commit** `feat(app): settings for recipients, valuation tier and PDF re-send`.

### Task 13: End-to-end and docs

**Files:**
- Modify: `app/test_e2e/` (new `settlement_e2e_test.dart`), `README.md` (operator: SMTP settings,
  monthly mail, settlement), `docs/superpowers/specs/2026-11-02-bar-tab-design.md` §10 (M4 done)
- Test: `app/tool/e2e.sh`

- [ ] **Step 1:** e2e test against the real server: opening count → booking → review → close →
  second review shows the counts as opening; mail `skipped` (no SMTP in e2e).
- [ ] **Step 2:** `app/tool/e2e.sh` → PASS; `server/tool/test.sh` and `app/tool/check.sh` clean.
- [ ] **Step 3: Commit** `test(app): settlement end to end` and `docs: operator notes for M4`.
