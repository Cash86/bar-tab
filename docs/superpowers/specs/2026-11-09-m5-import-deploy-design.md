# M5 – Legacy import, keg prices at booking, deployment

Status: approved by the maintainer, 2026-11-09. Builds on the main spec (`2026-11-02-bar-tab-design.md` §5 "Legacy
import", §10 item 5) and M4. Where this document differs from the main spec, it wins.

## 1. Why

The club switches from paper/Excel and an old Python script to bar-tab. The real persons, price
tiers and drinks come from the old script's CSV files; the server moves to its production host.
The real data never enters the repo (CLAUDE.md): the import reads local files and a local mapping
file, both outside git.

## 2. Goals

1. A server CLI command imports `user.csv` and `drink.csv` into an **empty, migrated** database.
2. Kegs are their own drink kind; their price is the purchase price, confirmed with every event
   booking (new).
3. The server runs in production behind Traefik, with backups-ready data volume and a healthcheck.
4. The tablet is paired to the production server.

## 3. Non-goals

- Importing legacy transactions (main spec: cut-over via opening count, M4 §5.0).
- SMTP setup (maintainer 2026-11-09: no mail for now; settlements are marked "keine Mail" and can
  be re-sent later).
- Moving to the club's final host (later; same steps, new DNS + re-pair).

## 4. Legacy import

### 4.1 Input
- `user.csv`: `Name,Rolle`, `Rolle` ∈ {`Aktiv`, `AH`, `hidden`}; `drink.csv`:
  `Sorte,Gruppe,Aktivenpreis,Altherrenpreis,Kastengröße`. Encoding cp1252 (repaired to UTF-8),
  CRLF or LF, header row. Prices euros with a decimal point → integer cents (exact decimal
  parsing, never float).
- A **mapping file** (JSON, kept outside git, path given on the command line) holds every
  club-specific decision, so the code stays generic:
  - `tiers`: names for the roles, in order, e.g. `{"Aktiv": "Aktive", "AH": "AHAH"}` (the
    maintainer's names, 2026-11-09; replaces the main spec's "Alte Herren").
  - `hidden_tier`: role whose tier hidden persons get (`"AH"` → AHAH).
  - `collective`: person names to flag as collective accounts.
  - `groups`: target group per legacy drink name (`"oetti_hell": "Bier"`, …); the groups
    themselves are created by the import if missing (name + colour from a fixed palette order).
  - `rename`: optional display-name overrides per legacy drink name (e.g. a misspelt keg).
  - `extra_drinks`: drinks not in the CSV, with group, prices per role and crate size.
- Legacy drink names are prettified (`oetti_apfelschorle` → `Ötti Apfelschorle`) unless renamed.
- `Gruppe = hidden` → hidden drink. Placeholder prices ≥ 10.000 € are imported as 0 and reported.
- Values longer than the M3 maximum lengths (person 20, drink 24, group 16, tier 16) are reported
  and the import stops before writing anything.

### 4.2 Behaviour
- Refuses to run on a database that already has persons or drinks (no merge, no duplicates).
- One transaction: everything or nothing.
- Prints a report: counts per tier/group, hidden persons, collective accounts, drinks with
  placeholder prices, renamed drinks.
- `--dry-run` prints the report without writing.

### 4.3 The club's mapping (maintainer 2026-11-09; lives only in the local mapping file)
For the record of decisions, without names: groups as today (Bier, Alkoholfrei, Limo, Wasser); all
lager/wheat/Ötti beers to Bier, alcohol-free beers to Alkoholfrei, all other Ötti soft drinks to
Limo, water to Wasser; the three kegs hidden in Bier, one renamed; three collective accounts on the
first tier; two hidden accounts on the second tier; one extra drink (malt beer, Limo, crate 20,
0,60 € / 1,20 €). Keg default prices = litres × €/l (3,00 Alpi, 2,50 other keg beer, 1,50 the
cheap keg).

## 5. Kegs (maintainer 2026-11-09)

- New drink property **"Fass" (`is_keg`)**, set in admin → Getränke as its own switch, stored on
  the server (Alembic migration), in the catalog API and in the app.
- A keg **never appears in the normal drink selection**, independent of `is_hidden`; it is
  bookable only in the admin event booking.
- In the event booking every keg line has a **price field** (purchase price), pre-filled with the
  keg's price for the chosen person's tier; a price is required for every keg line (0 allowed).
  The entered unit price is sent and is final (server never re-prices; no further API change).
- The same price applies to all tiers; the admin stores the usual purchase price in every tier so
  the field is pre-filled (import: litres × €/l via `price_overrides`).
- Inventory and deliveries treat kegs like any drink (units).
- Other hidden drinks keep today's behaviour (event booking only, tier price, no field).
- Import: the mapping lists kegs (`kegs`: legacy drink names); they are imported with
  `is_keg = true` (and not hidden).

## 6. Deployment

- Host: netcup with Traefik (network `proxy`, certresolver `http_resolver`), interim host
  `bar.example.org` (final: the club's final host). Public (no IP allowlist); protection by device key and
  admin PIN with lockout (maintainer 2026-11-09).
- Directory `/opt/containers/bar-tab`: repo checkout (or copied compose + image build), `.env` with
  real secrets (never in git), `docker-compose.override.yml` in variant (b) of the example.
- Carry-overs: entrypoint `chown -R` of existing `/data` contents; compose healthcheck on
  `/api/v1/health`; remove the unused `BARTAB_SECRET_KEY` (config, `.env.example`, e2e, docs).
- Backups: the daily SQLite snapshot from the main spec is **not built yet**; for now the operator
  doc describes copying `data/bartab.db` with `sqlite3 .backup` via cron. (Builder: a real backup
  job stays out of M5 unless trivial.)
- README operator section: install, update, import, pairing, backup.

## 7. Cut-over (operator steps, documented)

1. Deploy, run migrations (automatic), run the import with the local mapping file.
2. Set the admin PIN (initial PIN from `.env`, then change in admin).
3. Re-pair the tablet: admin → "Server neu koppeln" (works offline thanks to the local PIN hash
   once the admin logged in once) or clear app data and pair on first start.
4. Opening count, then normal operation.

## 8. Claude's calls (2026-11-09, from the builder check)

- **Empty database** = no price tiers, groups, persons or drinks (startup only seeds the admin PIN
  and the open period). The import creates the tiers in mapping order (`sort_order`).
- **Mapping additions:** `price_overrides` (cents per role per legacy drink name; used for the kegs:
  litres × €/l) and `word_replacements` (applied to prettified names, e.g. `Oetti` → `Ötti`), so the
  code needs no club-specific spelling rules. Prettify = split on `_`, capitalise each word, then
  apply `word_replacements`, then `rename`.
- **Strict mapping:** an unknown role, a CSV drink without a `groups` entry, a `collective` or
  `rename`/`price_overrides` name that matches nothing → the import aborts with a clear message
  and writes nothing. `hidden_tier` is a role key; hidden persons keep `is_hidden = true`.
  `Gruppe = hidden` sets the hidden flag; the target group still comes from `groups`.
- **Keg price field is app-only** (event booking UI + validation); the server keeps accepting the
  sent unit price as final.
- **Deployment:** `docker-compose.override.yml` is created on the host from variant (b) with the
  Traefik entrypoint `websecure`; the entrypoint's `chown -R /data` tolerates failure and logs it.
- **`BARTAB_SECRET_KEY` removal:** settings already ignore unknown variables, so an old `.env` keeps
  working.
- Re-pairing ("Server neu koppeln") exists since M3; no app change needed for §7.

## 9. Left to the builder

- Mapping-file schema details and validation messages.
- Group colours for groups created by the import.
- Whether deployment uses a checkout on the host or a built image copied over.
