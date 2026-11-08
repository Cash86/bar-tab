# Milestone 3 — Admin area: design

Status: agreed with the maintainer 2026-11-08 (chat + mockups). Extends §4.3 and §10 item 3 of
`2026-11-02-bar-tab-design.md`. The storno of bookings, the admin login/session and the design
choice already exist (issues #3, #4) and are not repeated here.

## 1. Intent

The club runs the bar from the tablet alone. Today master data only comes from `demo_data.py`, a
delivery or an event cannot be recorded, and a tablet cannot be moved to another server. M3 makes
the tablet self-sufficient for everything except the settlement (M4): an admin keeps persons,
drinks, groups and tiers up to date, records deliveries and event bookings, changes the PIN and,
rarely, re-pairs the tablet. The maintainer called it "just a simple admin menu": plain forms and
lists, no cleverness.

## 2. Goals, non-goals, anti-goals

Goals
- Admin home with entries for: Buchungen (exists), Lieferung, Lieferungen, Veranstaltung,
  Personen, Getränke, Gruppen, Preisstufen, Design (exists), Admin-PIN ändern; plus a discreet
  "Server neu koppeln" link.
- Master data CRUD with the maximum lengths enforced on server and app: person/collective name 20,
  drink 24, group 16, tier 16 characters.
- Deliveries recorded as crates + units, cancellable (storno) like bookings.
- Event bookings for one person over many drinks, incl. hidden persons and drinks.
- Re-pairing (new server URL / device key) without losing queued bookings, also when the current
  server is unreachable or rejects the key.
- Fix the M2 carry-over: one-frame flicker of the header total.

Non-goals (M4 or later)
- Settings for report/settlement recipients, re-sending the settlement PDF, inventory and
  settlement, monthly report.
- Editing bookings or deliveries (storno + re-entry only).
- Hard-deleting persons or drinks.
- A free colour picker.
- Admin functions offline (except re-pairing).

Anti-goals
- Losing a queued booking during re-pairing.
- History changing because master data changed (prices stay frozen on bookings; deactivation keeps
  history; nothing referenced is deleted).
- A re-pair entry that is easy to hit by accident.

## 3. Admin home

A grid of tiles (mockup "admin-ops", screen 1): Buchungen, Lieferung, Lieferungen, Veranstaltung,
Personen, Getränke, Gruppen, Preisstufen, Design, Admin-PIN ändern. The existing design choice
moves behind its "Design" tile. "Abmelden" stays in the app bar.

"Server neu koppeln" is **not a tile** (maintainer: it should be hidden or protected again — it is
hopefully done once). It is a small text link at the bottom of the admin home. Tapping it asks for
the PIN again (verified like a login), then shows a warning to confirm ("Das Tablet wird mit einem
anderen Server verbunden. Wartende Buchungen bleiben erhalten."), then the pairing form (§8).

Admin screens use the plain Material look with the current design's colours and fonts (as
decided in the themes spec), in all three designs alike. All strings in `app_de.arb`.

## 4. Master data

Each list: tap a row → edit dialog; "+ Neu" in the app bar → the same dialog empty. Names are typed
on the Android keyboard with a visible counter "n/max" and the limit enforced as you type; numbers
and prices use numeric input. Saving writes to the server; on success the tablet refreshes its
catalog at once (other tablets get it with their next periodic sync). A failed save keeps the
dialog open with an error message; nothing is changed locally.

### 4.1 Persons
- Segmented switch "Aktiv (n) | Deaktiviert (n)". The list is sectioned like the name list:
  Sammelkonten, one section per tier (in tier order), Versteckt; alphabetical within a section.
- Fields: name (≤ 20, required), price tier (required, one of the tiers), "Sammelkonto",
  "Versteckt".
- "Deaktivieren" in the dialog of an active person, "Aktivieren" in the dialog of a deactivated
  one. Deactivated persons disappear from the name list and the quick bar but keep their history;
  they stay selectable in the bookings filter (as today).
- Persons are never deleted.

### 4.2 Drinks
- Segmented switch "Aktiv | Deaktiviert". List sectioned by group (group order), drinks in their
  sort order; drag handle ≡ to reorder within a group. Each row shows crate size and the prices of
  all tiers.
- Fields: name (≤ 24, required), group (required), crate size (integer ≥ 1, required; 1 for kegs),
  a price per tier (integer cents ≥ 0, entered as euros with two decimals; **every tier
  required**), "Versteckt".
- A new drink goes to the end of its group. Moving a drink to another group puts it at the end of
  that group.
- "Deaktivieren" / "Aktivieren" as for persons. Drinks are never deleted.
- A price change affects only bookings made after a tablet has the new catalog (main spec §3).

### 4.3 Groups
- List in sort order with drag handle, colour dot and drink count (active + deactivated).
- Fields: name (≤ 16, required), colour.
- Colour: chosen from a **fixed palette of 12 colours** that read well on all three designs
  (mockup "master-data", screen 3; final values are Claude's pick, see §11). A group whose stored
  colour is not in the palette (demo or imported data) keeps it until a palette colour is chosen;
  the dialog shows the current colour as selected/extra swatch.
- Delete: only while the group has no drinks at all (also no deactivated ones); otherwise the
  delete action is disabled with a hint. New groups go to the end.

### 4.4 Price tiers
- List in sort order with drag handle and person count (active + deactivated). The order is the
  column order of the name list.
- Field: name (≤ 16, required).
- A new tier goes to the end and receives, for every drink, the price of the **first tier** (by
  sort order), so every drink always has a price for every tier. The admin adjusts prices per
  drink afterwards.
- Delete: only while no person (also no deactivated one) has the tier; deleting removes the tier's
  drink prices. The last remaining tier cannot be deleted.

### 4.5 Uniqueness and validation
- Names are unique per kind (persons, drinks, groups, tiers), compared case-insensitively after
  trimming. Deactivated entries count. The server answers a duplicate with 409 and the app shows
  "Name ist schon vergeben".
- The server validates everything (lengths, required fields, crate size, non-negative prices,
  prices for exactly the existing tiers, colour format, existing references) and answers with 422;
  the app validates the same rules before sending. Leading/trailing whitespace is trimmed, an
  empty name is invalid.
- Reordering sends the complete new order of the list (or of the drinks of one group); the server
  rewrites `sort_order` as 0..n-1.

## 5. Deliveries

### 5.1 Recording (mockup "admin-ops", screen 2)
- A list of all **active** drinks, including hidden ones, sectioned by group. Each row shows two
  fields: crates and loose units, and the resulting total in units (crates × crate size + units).
- Tapping a row selects it; the side panel shows the drink, its crate size, the two fields
  ("Kästen", "Einzeln", one focused) and the in-app keypad. The keypad edits the focused field.
- For drinks with crate size 1 only the units field is shown.
- App bar button "Lieferung buchen (n Getränke)", enabled when at least one total is > 0. It asks
  for confirmation ("n Getränke, m Einheiten buchen?") and then sends all non-zero lines in one
  request. On success it shows a confirmation and returns to the admin home; on failure the entered
  values stay so it can be retried.
- Each line becomes one stock entry of kind `delivery` in the open period, quantity in units.
  The request carries client-generated UUIDs so a retry never doubles a delivery.

### 5.2 List and storno (screen 3)
- "Lieferungen" lists the open period's deliveries, newest first: time, drink, units (with the
  crates/units split as entered, recomputed from the crate size is fine), "Stornieren".
- Storno exactly like bookings: in-app confirmation, recorded on the entry (`cancelled_at`,
  `cancelled_by_device_id`), never deleted, cannot be undone, cancelled rows stay greyed out and
  marked "storniert". Twice or in a closed period → 409 and "Storno nicht möglich", list reloads.
- Only deliveries of the open period are listed and cancellable. Opening and count entries are
  not shown here.
- Stock math (M4) must ignore cancelled deliveries (`cancelled_at IS NULL`); M3 adds this filter to
  every existing stock query.

## 6. Event bookings (mockup "admin-ops", screen 4)

- Step 1: pick a person — all active persons, hidden ones first, then collective, then the rest
  alphabetically.
- Step 2: the same quantity list as for deliveries, over all **active** drinks including hidden
  ones, each row showing the unit price of the person's tier and the line amount; the app bar shows
  the person (with tier) and the button "Buchen · <sum>". Confirmation, then send.
- The bookings go to the existing booking endpoint (`POST /bookings`) **directly online**, not via
  the offline queue and without the 15 s undo hold; booked with the person's tier prices from the
  catalog the tablet has (the sent unit price is final, as everywhere). One booking per drink line
  with its quantity, client UUIDs, `booked_at` = now from the clock. On failure the entries stay
  for a retry (same UUIDs, idempotent).
- They appear in "Buchungen" and are cancelled there. The running totals refresh after booking.

## 7. Admin PIN change

- Screen with three steps on the in-app keypad: current PIN, new PIN, new PIN again. New PIN 4–8
  digits (as today). Mismatch of the two new entries is caught in the app.
- The server verifies the current PIN (same lockout as the login: a wrong current PIN counts as a
  failed attempt) and stores the new hash. The admin session continues.
- On success this tablet replaces its local PIN hash (§8.1) at once. Other tablets keep the old
  local hash until their next successful online admin login (documented behaviour, acceptable).

## 8. Re-pairing

### 8.1 Local PIN hash
- On every successful online admin login (and after a PIN change) the tablet stores a salted,
  slow hash of the PIN (PBKDF2 or similar, library is the builder's choice) in app-private storage
  (the local Drift database, like the pairing). Never the PIN itself.
- It is used **only** for re-pairing when the server cannot verify the PIN.

### 8.2 Entry
- Online: admin home → "Server neu koppeln" link → PIN again (server login check) → warning →
  form.
- Offline: when the admin login fails because the server is unreachable **or rejects the device
  key** (401 on the device key), the PIN prompt checks the entered PIN against the local hash. On a
  match the admin area opens in a reduced mode that offers only "Server neu koppeln" (warning →
  form; the extra PIN step is skipped since the PIN was just entered). The same lockout rule as on
  the server applies locally (5 failures → 60 s). Without a stored local hash the offline path is
  not available and the prompt shows "Server nicht erreichbar" as today.
- A wrong PIN against a reachable server behaves as today (no local fallback).

### 8.3 Form and switch
- Same form as the first start: server URL and device key, pre-filled with the current values.
- "Koppeln" validates the new values against the new server exactly like the first start. Only on
  success the stored pairing is replaced; the old pairing stays in place on any failure, with the
  first-start error messages.
- After the switch: catalog is fetched from the new server, the sync loop continues against the
  new server, the admin session (if any) of the old server is dropped and the app returns to the
  name list.
- **Supported case only** (maintainer, 2026-11-08): the new server holds the same data as the old
  one (it moved, or the tablet got a new device key). Re-pairing to an empty or different server
  is not supported.
- **Queued bookings are kept** and pushed to the new server; the client UUID keeps this
  idempotent. Undo holds keep running as usual. A queued booking the new server rejects or answers
  with a conflict is handled exactly as today: it becomes final `rejected`/`conflict`, counts as
  failed in the sync indicator, stays stored locally and is not re-sent. No change to the sync
  state machine.
- Bookings that had already failed against the old server are not re-sent.
- Data cached from the old server (server-side tabs/running totals, rankings) is discarded and
  fetched again from the new server after the switch.
- The local PIN hash is kept (it belongs to the club's PIN, not to the server) and is overwritten
  at the next online admin login.

## 9. Header total flicker (M2 carry-over)

The header total briefly shows a wrong value for one frame because it combines two streams
(synced and queued bookings). It is computed from a single source so every emitted value is
consistent. No visible change other than the flicker being gone; a test pins that no intermediate
value is emitted when a booking moves from queued to synced.

## 10. Server API (shape left to the builder, within these rules)

- All new endpoints require an admin session (`X-Admin-Token`, as the storno endpoints) except
  where noted. Errors: 401 no/expired session, 404 unknown id, 409 conflict (duplicate name,
  already cancelled, period closed, delete of a referenced group/tier), 422 validation.
- Master data: create / update for persons, drinks (incl. prices), groups, tiers; activate /
  deactivate persons and drinks; delete groups and tiers (guarded); reorder drinks (per group),
  groups and tiers. All writes set `updated_at` from the clock, so the catalog ETag changes.
- Deliveries: batch create (client UUIDs, idempotent), list of the open period, cancel.
- PIN change: current + new PIN; lockout as login.
- Event bookings reuse `POST /bookings` (device auth), no new endpoint.
- Schema changes ship an Alembic migration with a test (`alembic upgrade head` on a fresh DB):
  `cancelled_at` / `cancelled_by_device_id` on stock entries. Case-insensitive name uniqueness is
  enforced in the repository (Unicode case folding is not available in SQLite; writes are already
  serialised by `BEGIN IMMEDIATE` and the single worker), so it needs no migration; existing
  duplicates (demo data has none) only block saving the duplicate under its name.
- The OpenAPI export and the app's API client are updated together.

## 11. Calls made by Claude (please check)

- Admin home as a tile grid; design choice moves behind a "Design" tile.
- Admin-PIN change is in M3; recipients and PDF re-send stay in M4.
- Delivery and event booking share one quantity list with the keypad in a side panel; one
  confirmation, one request.
- Deliveries list only the open period; storno rules copied from bookings.
- Event bookings go online through `POST /bookings`, without undo hold; listed and cancelled under
  "Buchungen".
- Person picker for event bookings: hidden first, then collective, then alphabetical.
- Only active drinks are offered in deliveries and event bookings.
- Groups and tiers can be deleted only while unreferenced; persons and drinks only deactivated.
- New tier copies the first tier's prices; the last tier cannot be deleted.
- Names unique per kind, case-insensitive, deactivated entries included.
- Fixed 12-colour palette for groups; the concrete colours are chosen during implementation and
  checked against all three designs.
- Reordering by drag handle; drinks reorder within their group.
- PIN change requires the current PIN; other tablets keep the old local hash until their next
  online admin login.
- Local PIN hash: salted slow hash in Drift; offline re-pair also when the server rejects the
  device key; local lockout 5 failures / 60 s; online re-pair asks for the PIN again.
- Case-insensitive uniqueness uses Unicode case folding (umlauts included); length limits count
  characters (code points), not bytes; uniqueness checked in the repository, not by a DB
  constraint; concurrent master-data edits from two tablets: last write
  wins, a reorder list that does not match the current set of ids → 409.

## 12. Acceptance criteria (each gets a test)

1. Each master-data kind can be created, edited and (where allowed) deactivated/reactivated or
   deleted; the tablet shows the change after saving without restart.
2. Over-long, empty, duplicate (case-insensitive) names are rejected by the server (422/409) and
   prevented by the app.
3. A drink cannot be saved without a price for every tier; a new tier gives every drink the first
   tier's price.
4. A referenced group or tier cannot be deleted (409); the last tier cannot be deleted.
5. Reordering persists and changes the order on the name list / drink selection.
6. A delivery of 2 crates + 3 units of a 20-crate drink stores 43 units in the open period; a
   retried request does not double it.
7. A cancelled delivery is excluded from stock queries; cancelling twice or in a closed period →
   409.
8. An event booking for a hidden person with a hidden drink is stored with the person's tier price
   and appears in "Buchungen"; a retry does not double it.
9. PIN change: wrong current PIN → refused and counted for lockout; success → the new PIN logs in,
   the old does not; the local hash is updated.
10. Offline re-pair: with the server unreachable (and with the device key rejected) the correct PIN
    opens the reduced admin with only "Server neu koppeln"; a wrong PIN does not; without a local
    hash it is not offered.
11. Re-pair keeps queued bookings; after the switch they are pushed to the new server exactly once;
    already failed bookings are not re-sent; cached tabs and rankings of the old server are
    replaced by the new server's; a failed validation leaves the old pairing in place.
12. The header total emits no intermediate wrong value when bookings move from queued to synced.
13. e2e (`app/tool/e2e.sh`): master data edit → catalog on the tablet; delivery + storno; event
    booking; re-pair against the real server.

## 13. Decisions made during implementation (Claude's calls, please check)

- The existing migration test `test_downgrade_removes_storno_columns` now downgrades to `0001`
  instead of `-1` (with `0003` present `-1` no longer reaches `0001`); assertions unchanged.
- The admin-home link to re-pairing stayed disabled until the re-pair flow was wired in.
- "Deaktivieren"/"Aktivieren" in the person dialog saves immediately, without a separate confirm.
- A price set that no longer matches the price tiers (`prices_incomplete`) shows "Preise passen
  nicht mehr zu den Preisstufen – bitte prüfen", keeps the entered values and refreshes the
  catalog; reordering is optimistic and reverts on failure.
- Deleting a group or tier asks for confirmation in a dialog, then calls the server; the palette
  was also checked against the chalk background `#232724`. The visual check of the palette on the
  three designs is still pending (to be done on the Linux target / the tablet).
- A delivery line keeps its UUID for retries only while its quantity is unchanged; an edited line
  gets a new id. A timeout followed by an edit can create two entries, which are visible in
  "Lieferungen" and can be cancelled.
- The deliveries tile shares the subtitle "ansehen & stornieren" with the bookings tile.
- A delivery smaller than one crate is listed as plain units.
- "Person ändern" in the event booking returns to the picker and resets the lines; each line is
  capped at 999 units.
- PBKDF2 stays at 20 000 iterations (about 89/74 ms on desktop, estimated 0.5-1 s on the tablet);
  to be checked on the tablet on 2026-11-09.
- The re-pair form keeps the first-start button label "Verbinden".
- The local PIN lockout survives leaving the gate; the online PIN prompt has no local fallback
  when the server is unreachable.
- A sync of the old service that is still running during a re-pair may write old tabs after they
  were cleared; the next sync replaces them (same-data assumption, §8.3 of this spec).
- A wrong local PIN shows the existing "PIN falsch" instead of "Falsche PIN".
- "+ Neu" sits in each list's header (next to the Aktiv/Deaktiviert switch), not in the app bar,
  the same on every master-data screen. Without a price tier (persons) or a group (drinks) it is
  disabled with the hint "Zuerst eine Preisstufe anlegen" / "Zuerst eine Gruppe anlegen".
- AC 7: the stock-query half moves to M4, since no stock query exists yet; the obligation is
  recorded in the main spec §10 item 4. M3 covers storno twice / in a closed period (409).
- AC 5: the order on the name list / drink selection is covered link by link: the server reorder
  tests persist `sort_order`, and the name-list and drink-selection tests order by `sortOrder`.
- A server 5xx on admin login is treated like unreachable and also opens the offline re-pair path
  (reduced mode with only "Server neu koppeln", local PIN hash required).
- Event booking: a retried line keeps its id and its `booked_at` (the server compares both), an
  edited line gets a new id and the current time. An entered drink without a price for the
  person's tier blocks booking (button disabled, hint "Kein Preis für <tier>: <drinks>").
- After an event booking or a master-data save the app awaits a sync already running, then runs
  one more, so the fetched tabs/catalog surely postdate the write.
- A delivery line is capped at 99 999 units (server `MAX_DELIVERY_UNITS`); a drink price above
  10 000 € is refused in the dialog ("Höchstens 10.000,00 €").
- A rejected reorder (e.g. 409 `order_mismatch`) reverts and reloads the catalog, so the next try
  starts from the server's data.
