# M4 – Inventory, settlement, PDF, mail, monthly report

Status: approved by the maintainer, 2026-11-09. Builds on the main spec (`2026-11-02-bar-tab-design.md`, §3, §4.4, §5,
§10 item 4) and on M3 (`2026-11-08-m3-admin-design.md`). Where this document differs from the main
spec, this document wins; the main spec is updated with the changes listed in §9.

## 1. Why

Until now the club ran the bar with paper lists and Excel sheets. Two people need numbers from
bar-tab:

- The **Bierwart** (bar keeper) should count the stock once a month and check it against what the
  system expects. In practice the count is often late, so bar-tab must nag without blocking.
- The **Kassenwart** (treasurer) debits the members' bank accounts. bar-tab never handles money;
  the treasurer only needs the **amount per person** and the **total shrinkage** ("Schwund").

**Billing happens only with an inventory** (maintainer, 2026-11-09): a settlement closes the
period that ends with an inventory count. The monthly mail is information only, never a basis for
debiting.

## 2. Goals

1. Inventory & settlement as one guided admin flow on the tablet (main spec §4.4 "Inventory &
   settlement", unchanged steps 1–4).
2. Settlement PDF mailed to all recipients; re-send from admin.
3. Shrinkage is **valued in euros** (new, maintainer 2026-11-09) and shown per drink, per group
   and as a total.
4. Monthly interim mail to all recipients, with an "inventory overdue" notice.
5. Recipient list editable in admin.
6. Carry-overs: every stock, settlement and monthly-report figure excludes cancelled bookings
   (`bookings.cancelled_at IS NULL`) and cancelled deliveries (`stock_entries.cancelled_at IS
   NULL`); the settlement PDF has a storno section.

## 3. Non-goals

- Debiting, bank files (SEPA), CSV export.
- Charging shrinkage to persons; the club decides that outside the app.
- Separate recipient lists per mail type.
- Purchase prices.
- Editing a closed period.

## 4. Anti-goals

- A settlement that loses or double-counts a booking (queued, late or cancelled).
- A failed mail that leaves the period half-closed, or a retry that closes a second period.
- A monthly mail that is skipped or sent twice because of a restart.
- Figures that differ between the review screen, the PDF and the mail.

## 5. Settlement

### 5.0 Opening count (cut-over, maintainer 2026-11-09)
- A separate admin flow "Anfangsbestand erfassen", available only while no settlement has ever
  been closed.
- Counting works exactly like step 2 of the settlement (same keypad, same local draft).
- Confirm stores the counts as the opening stock of the open period (replacing an earlier opening
  count). Nothing is closed, billed or mailed; no PDF.
- The date of the latest opening count is the "last inventory" for the overdue notice (§6) until
  the first settlement. Without any opening count, it is the start of the open period.

### 5.1 Flow (tablet, admin)
Unchanged from main spec §4.4:
1. The tablet pushes all queued bookings. If it cannot reach the server, or the queue cannot be
   emptied, the flow does not start and says why. Undo holds (15 s) are cleared first, i.e. held
   bookings are released for sync immediately (M3 carry-over).
2. Count per drink, including hidden drinks (kegs), as crates + loose units with the in-app
   keypad, like a delivery. Inactive drinks with an expected stock other than 0 are listed too.
3. Review: per drink expected / counted / shrinkage (units) and shrinkage value; group subtotals;
   totals (amount owed by all persons, shrinkage value). Nothing is stored; counts can be
   corrected.
4. Confirm → the server closes the period atomically: stores the counts, closes the period, opens
   the next one with the counts as opening stock, generates the PDF and mails it. Bookings that
   arrive later for the closed time land in the new period marked `is_late` (existing behaviour).

Every drink must have a count before the review (0 is a valid count).

### 5.2 Shrinkage value
- `shrinkage = expected − counted` (units, may be negative = more found than expected).
- Value = `shrinkage × price of the drink in the valuation tier`, integer cents.
- **Valuation tier**: an admin setting "Schwund bewerten mit Preisstufe". Default: the tier with
  the lowest `sort_order` (for the club: "Aktive"). Stored in `app_settings`.
- A drink without a price in the valuation tier counts as 0 € and is marked in review and PDF.
- Negative shrinkage gives a negative value and offsets the others in the totals.

### 5.3 Settlement PDF
Content (main spec §5 "Settlement PDF", plus the new parts in bold):
- Header: period from/to (local time, `BARTAB_TZ`), created at.
- Per price tier, one row per person: quantity per drink group and amount owed; tier subtotal.
  Hidden accounts are listed separately. Grand total of amounts owed.
- **Shrinkage section**: per drink opening, delivered, booked, expected, counted, shrinkage units,
  **shrinkage value**; group subtotals; **total shrinkage value**; the valuation tier's name.
- Deliveries of the period (not cancelled).
- **Storno section**: cancelled bookings of the period (booked at, cancelled at, person, drink,
  quantity, amount) and cancelled deliveries.
- Appendix: per person per drink breakdown.

The settlement figures come from one server-side computation used by the review endpoint, the PDF
and the mail, so they cannot differ.

### 5.4 Mail and re-send
- Recipients: the single recipient list (§7). Subject and body German, from l10n-free server
  templates (server strings are not part of the app's `.arb` files).
- If sending fails, the period stays closed; admin shows the failure and offers "PDF erneut
  senden". Admin can always re-send the PDF of the **last** closed period.
- No recipients or no SMTP configured: the settlement still closes; admin says the mail was not
  sent.

## 6. Monthly interim mail

- Sent on `BARTAB_MONTHLY_REPORT_DAY` at `BARTAB_MONTHLY_REPORT_TIME` (local), by a scheduler in
  the server process; the last send is recorded in the DB so restarts never skip or duplicate a
  month (main spec §5). Plain-text body.
- Content: consumption per person and drink since the last settlement, **amount per person so
  far**, expected stock per drink. Marked clearly as "Zwischenstand, keine Abrechnung".
- **Inventory overdue notice** (maintainer, 2026-11-09): when the last inventory (the start of
  the open period) is more than one calendar month ago, the mail starts with
  "Inventur überfällig seit X Tagen", X = days since that date plus one month.

## 7. Recipients and settings (admin)

- New admin tile "Einstellungen" (or extension of an existing settings place; builder's call)
  with: recipient list (any number of e-mail addresses, added and removed one by one, simple
  syntax check; maintainer 2026-11-09), valuation tier,
  "PDF erneut senden" with the last settlement's date and mail status.
- All recipients get both mails (maintainer, 2026-11-09).

## 8. Constraints

- Layers, TDD, migrations (Alembic + Drift where needed), money in integer cents, `Clock` for
  time, config only via `BARTAB_*` (SMTP settings already exist in `config.py`).
- Admin screens use the standard look (fix of 2026-11-09).
- Admin functions need the server (main spec §4.4).
- Single uvicorn worker (scheduler and PIN lockout live in-process).

## 9. Changes to the main spec

- §3 "Shrinkage is reported in units only" → shrinkage is also valued in euros (§5.2 here).
- §4.4 Settings: one recipient list instead of separate lists.
- §5 Monthly report: adds amount per person so far and the overdue notice.
- §11 "Shrinkage in units only, not valued" → superseded.

## 10. Claude's calls (2026-11-09, from the builder check; maintainer to review)

- **Count draft:** counts entered in step 2 are kept on the tablet as a local draft (Drift) that
  survives admin logout (2-min idle), screensaver and app restart, until the settlement is
  confirmed or the draft is discarded. Re-entering the flow offers to continue the draft. The idle
  rules stay unchanged.
  The draft remembers the open period (`period_id` of `GET /admin/stock`); a draft of another
  period (closed meanwhile, e.g. after "Status unklar") is dropped, not restored. If the review is
  refused because the drinks to count changed, the app returns to the count with the new list,
  keeps the counts of drinks still listed and says "Getränkeliste hat sich geändert – bitte
  Zählung prüfen".
- **Stale review:** the review carries a token over the figures (period id + hash). Confirm with a
  token that no longer matches (new sync, storno, delivery, price or tier change meanwhile) is
  refused with 409; the app reloads the review and says so. The same token makes a retried
  confirm idempotent (no second close).
- **Snapshot at close:** counts, shrinkage values, the valuation tier name and all PDF figures are
  stored with the closed period at close time; later price or setting changes never alter a
  closed settlement. Re-send uses the snapshot.
- **Valuation tier gone:** if the chosen tier is deactivated, valuation falls back to the active
  tier with the lowest `sort_order`; review and PDF name the tier actually used.
- **Monthly mail retries:** a month counts as sent only after a successful send. On failure or a
  missed time (server down) the scheduler retries hourly, also right after startup, until the end
  of that month; only the latest due month is sent, no catch-up of older ones. Without SMTP or
  recipients nothing is sent and the month stays due.
- **Totals:** persons are listed only if they have bookings in the period; deactivated persons
  with bookings are listed in their tier. Totals: persons (visible incl. collective accounts),
  hidden accounts, and the grand total of both, each shown separately.
- **Blocking bookings:** only pending (queued or held) bookings block the start of the settlement;
  final `rejected`/`conflict` bookings do not block but are shown as a warning count.
- **No overdue warning in the app**; the notice lives only in the monthly mail.
- **Monthly report config:** the day must be 1-28 and the time HH:MM; validated at startup.
- **Token and count list:** the review/close token ignores the computation time; a changed
  drinks-to-count list between review and close is a stale review (409).
- **Count validation:** counts for drinks not in the count list are rejected; the opening count
  also needs every listed drink; a drink counted twice is rejected (422).
- **Tiers:** price tiers have no "inactive" state; the valuation fallback applies when the chosen
  tier no longer exists.
- **PDF failure:** a failed PDF render after close is reported as a failed mail (re-send available).
- **Close timeout:** the tablet waits up to 60 s for the close answer; without an answer it shows
  "Status unklar – bitte erneut abschließen" and a retry replays the same close safely.
- **Number format:** settlement and PDF show German thousands separators (1.234,56 €).
- **Recipients:** duplicates are ignored; e-mail syntax is checked by the server.
- **Opening count cuts off stock (maintainer ruling):** while no settlement has been closed, stock
  movements of the open period count only from the latest uncancelled opening count on (bookings
  by `booked_at`, deliveries by `created_at`); amounts owed still use all bookings of the period.

## 11. Left to the builder

- PDF library (pure Python preferred, must run in the existing Docker image) and layout.
- Whether the PDF is stored in the data volume or regenerated from the DB for re-send (same
  bytes not required, same figures required).
- API shape of the review/close/re-send endpoints, following the existing admin API style.
- Mail transport details (STARTTLS/SSL by port).
