# bar-tab — Design

**Status:** draft for approval · **Date:** 2026-11-02 · **Repo:** `github.com/Cash86/bar-tab` (public, to be created)

## 1. Intent

A club runs a self-service bar. Members take a drink from the fridge and record it on a shared
device; at the end of a billing period the beer steward ("Bierwart") counts the stock and tells the
treasurer ("Kassenwart") what each person owes.

Today this runs on a laptop with an unreviewed Python/Tkinter script writing CSV files. It works
but is fragile: umlauts break it, a crash or a wrong click during settlement leaves stray files,
stock per variety is wrong (group bookings decrement an arbitrary variety), there is no undo, no
backup, and an SMTP password sits in the source.

**bar-tab** replaces it with an Android tablet app (Flutter) and a small server (Python/FastAPI)
that holds the data, sends a monthly interim report and produces the settlement PDF.

It is built as a **public, reusable project**: any club can deploy it. Nothing club-specific lives
in code — names, drinks, groups, price tiers, recipients and secrets are data (database) or
configuration (`.env`).

### What success looks like
- Recording a drink is as fast as today: tap name, tap drink, walk away.
- No booking is ever lost, even with flaky Wi-Fi.
- Settlement is one guided flow on the tablet that ends with a PDF in the treasurer's inbox, and
  cannot half-fail.
- Stock and shrinkage ("Schwund") are correct per variety.
- Another club can deploy it from the README without touching code.

## 2. Goals, non-goals, anti-goals

**Goals (v1)**
- Tablet kiosk app: name list → drink selection → booking, with multi-tap quantities and a short
  grace period to discard.
- Admin area behind a PIN: deliveries, inventory + settlement, event bookings, master data,
  booking corrections, settings.
- Server: source of truth, sync API, monthly interim mail, settlement PDF mail, backups.
- Offline-first bookings on the tablet.
- One-off import of the legacy CSV master data.
- README + operator docs good enough for a third party.

**Non-goals (v1)**
- Collecting money / payment integration — the treasurer bills outside the app.
- Personal logins, booking from members' own phones (**planned final milestone**, see §10).
- Differentiated admin roles (one shared admin PIN is enough for now).
- CSV export of the settlement (PDF only; CSV can be added later).
- iOS (Flutter keeps the door open; not built or tested in v1).
- Multi-club hosting in one deployment — one deployment = one club.

**Anti-goals (would make it a failure even if it works)**
- Booking takes more taps or more waiting than the old script.
- A booking silently disappears or is counted twice.
- Any secret, real member name or club identifier ends up in the public repo.
- The admin flows are so involved that the beer steward goes back to paper.

## 3. Domain

| Concept | Meaning |
|---|---|
| **Price tier** | A named price category, e.g. "Aktive", "Alte Herren". Freely defined per deployment. |
| **Person** | Someone who books. Has exactly one price tier. Flags: `hidden` (not on the name list, bookable only from admin — e.g. "AH-Kasse (Veranstaltung)"), `collective` (shared account such as "Aktivitas", shown in a top row), `active` (deactivated persons disappear from the list but keep their history). |
| **Drink group** | Display grouping with a sort order and a colour, e.g. Bier, Alkoholfrei, Ötti, Wasser. Purely presentational + used for report subtotals. |
| **Drink** | A concrete variety ("Apfelschorle"). Belongs to one group. Has one price per price tier, a crate size (units per crate; 1 for kegs), a sort order, and flags `hidden` (only bookable via event booking — e.g. kegs) and `active`. |
| **Booking** | Person × drink × quantity × unit price at booking time × timestamp. Positive quantity = consumption. The price is frozen at booking time; later price changes never alter history. |
| **Delivery** | Drink × quantity (in units) added to stock. |
| **Inventory count** | Counted stock per drink at settlement. |
| **Settlement period** | Starts with an inventory count (opening stock), ends with the next one. Closing a period produces the settlement; the closing count becomes the next period's opening stock. Nothing is deleted. |

**Stock math, per drink, per period:**
`expected = opening + deliveries − booked quantity` · `shrinkage = expected − counted`
Group values are sums of their drinks. Stock is tracked in units (bottles/kegs).

Prices are entered and stored as integer cents.

**Which price is billed:** the unit price the tablet showed and stored with the booking is final.
The booking request carries it; the server records it as sent (device-authenticated) and never
re-prices. A price change made while a tablet is offline therefore only affects bookings made
after that tablet has synced the new price. No effective-dated price history is needed.

**Shrinkage is reported in units only** (as in the legacy system), per drink and per group. It is
not valued in money and not charged to anyone by the app; the club decides that outside.

## 4. Tablet app (Flutter)

Landscape, kiosk-style (Android screen pinning, screen kept awake). Visual language from the
approved mockups: dark bottle-green surface, each drink group / price tier carries one colour as a
rail and as an accent on its tiles, condensed type for names, prices only on drink tiles.

### 4.1 Name list (start screen) — approved "variant B"
- Top row: collective accounts.
- Below: one column per price tier (today: Aktive | Alte Herren), alphabetical within each column.
  With more than two tiers, columns are added side by side.
- Overflow: tiles shrink first (3 → 4 per row, flatter), then each column scrolls independently
  with a fade hint; the collective row stays fixed. Deactivating people keeps the list short.
- An unobtrusive "Admin" button bottom-right opens the PIN prompt.

### 4.2 Drink selection — approved
- Header: person's name (large), their price tier, and their running total since the last
  settlement.
- One row per drink group (group name on a coloured rail, no price on the rail), drink tiles in a
  grid; each tile shows the price for this person's tier. Hidden drinks never appear here.
- **Tapping a tile adds one** to a pending order; a counter badge shows the quantity on the tile.
  Several drinks can be combined in one order.
- A bar at the bottom shows the pending order and its total, with **"Verwerfen"** (discard all) and
  **"Fertig"** (book now).
- **On the third tap** on the same drink, a quantity sheet slides in from the right: −/+ buttons,
  a large number field, an in-app numeric keypad (no system keyboard), and a "Kasten (n)" key that
  sets the drink's crate size. Actions: **"Buchen"** books the *whole* pending order (same as
  "Fertig"); **"Weitere Getränke"** closes the sheet, keeps the entered quantity and returns to the
  drink grid. The sheet has no discard button — discarding stays on the bottom bar only, so a
  whole order cannot be thrown away by accident. Quantity 0 removes that drink from the order.
- **8 seconds after the last tap** the pending order is booked automatically and the app returns
  to the name list. Every tap restarts the 8 seconds. While the quantity sheet is open, the timer
  is paused (*builder's call, see §12*).
- "Andere Person" returns to the name list and discards the pending order.

There is no undo after booking on the main screens; wrong bookings are corrected in admin (§4.3).

### 4.3 Admin area
Entered with the shared admin PIN. Auto-logout after 2 minutes without interaction. Admin
functions require a server connection (only bookings work offline).

- **Delivery:** per drink, crates + loose units → stock increases.
- **Inventory & settlement** (one guided flow):
  1. Tablet pushes all queued bookings; if it cannot reach the server, the flow does not start.
  2. Count per drink (incl. hidden drinks such as kegs), entered as crates + units with the in-app
     keypad.
  3. Review screen: expected / counted / shrinkage per drink and per group, plus the period's
     totals. Nothing is persisted yet; the user can go back and correct counts.
  4. Confirm → server closes the period atomically, stores the counts as the new opening stock,
     generates the PDF and mails it. If the mail fails, the period is still closed and the PDF can
     be re-sent from admin.
- **Event booking:** pick a person (typically a hidden account), enter quantities per drink
  including hidden drinks; booked with that person's tier prices.
- **Bookings:** list of the current period's bookings (filter by person); a booking can be
  cancelled (storno), which is recorded as a cancellation, not a delete.
- **Master data:** create / edit / deactivate persons, price tiers, drink groups (order, colour),
  drinks (group, prices per tier, crate size, hidden, order). Nothing referenced by bookings is
  hard-deleted.
- **Settings:** recipients of the monthly report and of the settlement (email addresses), change
  admin PIN, re-send last settlement PDF.

### 4.4 First start
The APK is generic. On first launch it asks for the server URL and a device key, validates both
against the server, then syncs master data.

### 4.5 Offline behaviour
- Bookings are written to a local Drift database first, each with a client-generated UUID, then
  pushed in the background; the server treats the UUID as idempotency key, so retries never
  double-count.
- Master data is cached locally and refreshed on start, after admin edits, and periodically.
- The running total in the header is computed locally from synced + queued bookings of the
  current period (a plain sum of stored prices — no business rules duplicated in the app).
- A small, non-alarming indicator shows when bookings are waiting to be sent.

## 5. Server (Python)

Python 3.12, FastAPI, SQLAlchemy + Alembic, SQLite, WeasyPrint, pytest — a pattern already proven
in another of the maintainer's services (reference for structure, Docker and Traefik setup;
nothing club-specific is copied).

**The server owns every money and stock calculation**: running totals per period, expected stock,
shrinkage, settlement figures, PDF content. The app only displays.

- **API:** JSON over HTTPS, versioned under `/api/v1`. The OpenAPI schema FastAPI generates is
  the contract; the app's DTOs are generated from it, and a test fails when app and schema
  diverge.
- **Auth:** each tablet sends a device key (bearer token). Admin endpoints additionally require an
  admin session obtained by posting the PIN; the PIN is stored as a slow hash in the DB. Rate
  limiting / backoff on wrong PINs. The auth layer is built around a "principal" so that personal
  member logins (§10) can be added without reshaping the API.
- **Period assignment:** a booking belongs to the period that is open when the server receives it.
  Because settlement first flushes the settling tablet's queue, this only matters for a second
  device that was offline across a settlement; such late bookings land in the next period and
  are marked as late in that period's report.
- **Monthly interim report:** on the 1st of each month (time configurable), a mail to the
  configured recipients with consumption per person and drink since the last settlement and the
  expected stock per drink. Explicitly *not* a settlement — no inventory, no shrinkage. The
  scheduler runs inside the server process and records the last send in the DB, so restarts never
  skip or duplicate a month.
- **Settlement PDF:** per price tier, one row per person with quantity per drink group and amount
  owed; hidden accounts listed separately; shrinkage and stock (opening, deliveries, booked,
  expected, counted) per drink with group subtotals; deliveries of the period. Detailed per-drink
  per-person breakdown as an appendix (*builder's call on layout*).
- **Backups:** daily SQLite snapshot (online backup API) into a backup directory in the data
  volume, rotating; off-site copy is the operator's job and documented.
- **Legacy import:** a CLI command that reads the old `user.csv` and `drink.csv`, repairs the
  broken encoding (cp1252/latin-1 → UTF-8), maps roles to price tiers and `hidden` flags, and
  creates groups from the CSV. Legacy format (comma-separated, header row):
  - `user.csv`: `Name,Rolle`; `Rolle` ∈ {`Aktiv`, `AH`, `hidden`}. `Aktiv` → tier "Aktive",
    `AH` → tier "Alte Herren", `hidden` → hidden person on tier "Alte Herren" (adjustable in admin).
    Known collective accounts (`Aktivitas`, `Couleurbesuch`, `Fuxenkasse`) are flagged
    `collective` via a CLI option, not hard-coded.
  - `drink.csv`: `Sorte,Gruppe,Aktivenpreis,Altherrenpreis,Kastengröße`; prices as euros with a
    decimal point, crate size integer. `Gruppe` = `hidden` → hidden drink (group assigned via a
    CLI option or a catch-all "Fass" group); placeholder prices ≥ 10,000 € are imported as 0 and
    reported for manual fixing. Drink names are machine-style (`oetti_apfelschorle`) and are
    prettified (`Ötti Apfelschorle`) for review in admin.
  - Test fixtures use invented names in this exact format. Regrouping (e.g. Ötti Hell/Weizen → Bier) is done afterwards in
  admin. Legacy transactions are **not** imported: cut-over happens by running a final settlement
  in the old system and then an initial inventory in bar-tab.

## 6. Configuration and secrets

`.env` (never committed; `.env.example` with placeholders is):
server public URL, timezone, SMTP host/port/user/password/sender, device keys, initial admin PIN
(used only to seed an empty DB), monthly report day/time.

Database (editable in admin): everything else — persons, price tiers, groups, drinks, prices,
recipients, admin PIN hash.

The repo contains only invented demo data (seed for local dev and tests). Real data, legacy CSVs
and the brainstorming mockups (`.superpowers/`) are git-ignored.

## 7. Repository

Monorepo `bar-tab`, MIT licence, English for code, comments, docs and commits; UI German first
with Flutter l10n (`.arb`) from day one.

```
app/                 Flutter app
server/              FastAPI service, Dockerfile, Alembic migrations, tests
docs/                operator guide, architecture, specs (docs/superpowers/specs)
docker-compose.yml   server + volume; Traefik via override example
.env.example
README.md            what it is, screenshots, quick start, links to docs
CLAUDE.md            project rules for agents (see §8)
```

CI (GitHub Actions) runs only the part that changed (path filters).

## 8. Engineering rules (adapted from the maintainer's Flutter projects)

Adopted: English repo language / German chat; TDD — tests first, every acceptance criterion has a
test that goes red when broken; existing tests are never weakened to get green; ask instead of
inventing on ambiguity; Conventional Commits; `flutter analyze` / `dart format` / `ruff` clean;
UUIDs and `createdAt`/`updatedAt` on entities; no `DateTime.now()` (clock wrapper) on either
side; every schema change ships a tested migration (Drift on the app, Alembic on the server).

Flutter layering: `domain/` pure Dart, `data/` implements repositories,
`presentation/` via Riverpod; models with `freezed`; mocks with `mocktail`; no hard-coded UI
strings.

Dropped (game-specific): Flame, game time, multiplayer fields, release/tester branch model,
CI-minute budget rules.

## 9. Deployment

First target: the maintainer's netcup server, Docker Compose behind the existing Traefik, like the
maintainer's other services. Moving servers = copy the data directory and `.env`, `docker compose up -d`.
The README walks a third party through: DNS + TLS, `.env`, first start, creating a device key,
installing the APK on the tablet (sideload), first-start pairing, importing or entering master
data, enabling screen pinning.

## 10. Milestones (order, not dates)

1. Server core: domain, DB, sync API, auth — test-driven.
2. App: name list + drink selection + offline queue against the real API.
3. Admin: master data, deliveries, event bookings, booking corrections.
4. Inventory & settlement flow + PDF + mail; monthly interim report.
5. Legacy import, deployment on netcup, README/operator docs; cut-over from the old script.
6. **Later:** members book from their own phones — personal login, same Flutter app or a phone
   layout of it. Out of scope until 1–5 run in production.

## 11. Decisions made by the maintainer
Flutter for the tablet; Android first; server on netcup now, movable later; monthly mail = rough
interim update, settlement only via manual inventory; booking per exact variety, groups for
display; drink selection layout "variant B" with group rows; prices on tiles only; multi-tap with
counter, quantity field from the third tap; undo/grace period OK; name list "variant B" (columns
per tier) with shrink-then-scroll overflow; one shared admin PIN; hidden persons and hidden drinks
editable in admin; price tiers (Aktive/AH) with different prices; settlement as PDF only; Python
server; one monorepo; public repo `bar-tab` under `Cash86`; all configuration in DB or `.env`.

## 12. Calls made by Claude (please check)
- Auto-book 8 s after the last tap; "Fertig" books immediately; several drinks per order.
- Quantity sheet: "Buchen" books the whole order, "Weitere Getränke" returns to the grid; no
  discard inside the sheet.
- Tablet's stored unit price is final; no price history.
- Shrinkage in units only, not valued or charged (as in the legacy system).
- Legacy hidden persons default to the "Alte Herren" tier.
- In-app keypad and "Kasten (n)" key in the quantity sheet.
- Admin auto-logout after 2 minutes; admin functions online-only.
- Corrections via storno in admin instead of undo after booking.
- Server owns all calculations; app only sums stored prices for the header.
- Late bookings from an offline second device go into the next period, marked as late.
- Legacy transactions not imported; cut-over via final old settlement + initial inventory.
- Monthly report on the 1st; interim mail as plain mail body, settlement as PDF attachment.
- SQLite + daily snapshot backups; MIT licence.

## 13. Left to the builder
Exact API shape, DB schema, package choices within the stack above, PDF layout, sync interval,
whether the 8 s timer pauses while the quantity sheet is open, colours per group (configurable or
from a palette), tablet minimum Android version (Flutter default), CI details.
