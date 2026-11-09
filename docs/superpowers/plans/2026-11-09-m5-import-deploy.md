# M5 Import, Kegs and Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import the legacy CSV data through a generic CLI with a local mapping file, add kegs as
their own drink kind with a purchase price entered per event booking, and make the server ready
for production behind Traefik.

**Architecture:** Parsing and mapping of the legacy files is pure domain code
(`bartab/domain/legacy.py`); one persistence function writes the result in a single transaction;
the CLI wires both. `is_keg` is a new drink column carried through API, catalog and app; the app
filters kegs out of the drink grid and adds a price field to the event booking.

**Tech Stack:** FastAPI, SQLAlchemy, Alembic, argparse CLI; Flutter, Riverpod, freezed; Docker
Compose, Traefik.

**Spec:** `docs/superpowers/specs/2026-11-09-m5-import-deploy-design.md`

## Global Constraints

- No real names, club names or real data in the repo; tests and fixtures use invented data.
- Money is integer cents; legacy euro strings are parsed with `decimal.Decimal`, never float.
- Max lengths: person 20, drink 24, group 16, tier 16.
- Schema change → Alembic `0005` + migration test; API change → `server/tool/export_openapi.py`,
  `api/openapi.json`, app DTO + `dto_contract_test.dart`.
- UI strings only in `app/lib/l10n/app_de.arb`; admin screens standard look.
- `server/tool/test.sh`, `app/tool/check.sh` clean; `app/tool/e2e.sh` before merge.
- Conventional Commits ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A legacy file in cp1252 with umlauts and CRLF → names come out correctly in UTF-8 (Task 2
   test `test_reads_cp1252_crlf`).
2. A mapping typo (collective name, group entry, keg name) → import aborts, database untouched
   (Task 2/3 tests `test_unknown_mapping_name_aborts`, `test_import_is_all_or_nothing`).
3. Running the import twice → second run refused, nothing duplicated (Task 3
   `test_refuses_non_empty_database`).
4. A keg left without a price in the event booking → "Buchen" disabled (Task 5).
5. A keg never shows up on the drink selection screen even if not hidden (Task 4).

---

### Task 1: Server – `is_keg` drink property

**Files:**
- Create: `server/alembic/versions/0005_drink_is_keg.py`
- Modify: `server/bartab/persistence/models.py` (Drink.is_keg bool, default False, server_default
  false), `server/bartab/persistence/master_data.py` (create/update drink take `is_keg`),
  `server/bartab/api/schemas.py` (drink out + write schemas gain `is_keg: bool`, write default
  `False`), catalog output, `server/bartab/domain/...` catalog types if drinks pass through domain,
  `api/openapi.json`
- Test: `server/tests/persistence/test_migrations.py` (0005), `server/tests/api/test_admin_master_data.py`,
  `server/tests/api/test_catalog.py`

**Interfaces:** Produces JSON field `is_keg` on every drink in `GET /catalog` and admin drink
responses; drink create/update accept `is_keg` (optional, default false).

- [ ] **Step 1: Failing tests:** migration adds `drinks.is_keg` (existing rows false); create drink
  with `is_keg: true` round-trips through admin API and catalog; update can toggle it; omitting it
  on create gives false.
- [ ] **Step 2–4:** run FAIL → implement → `server/tool/test.sh` PASS; export OpenAPI.
- [ ] **Step 5: Commit** `feat(server): mark drinks as kegs`.

### Task 2: Domain – legacy parsing and mapping

**Files:**
- Create: `server/bartab/domain/legacy.py`
- Test: `server/tests/domain/test_legacy.py` (invented CSV content as strings/bytes)

**Interfaces:**
- `class LegacyError(Exception)` (message lists every problem found, German-free, English).
- `@dataclass(frozen=True) Mapping`: `tiers: dict[str,str]` (role → tier name, ordered),
  `hidden_tier: str` (role key), `collective: list[str]`, `groups: dict[str,str]` (legacy drink →
  group), `group_order: list[str]`, `kegs: list[str]`, `rename: dict[str,str]`,
  `word_replacements: dict[str,str]`, `price_overrides: dict[str, dict[str,int]]` (legacy drink →
  role → cents), `extra_drinks: list[ExtraDrink]` (`name, group, crate_size, prices: dict[str,int]`,
  `is_keg: bool = False`).
- `parse_mapping(data: dict) -> Mapping` (validates types/keys; unknown keys → LegacyError).
- `decode_legacy(raw: bytes) -> str` – cp1252 → str, CRLF/LF normalised.
- `prettify(legacy_name: str, mapping: Mapping) -> str` – `rename` wins; else split on `_`,
  capitalise each word, then `word_replacements` per word (`oetti_hell` → `Oetti Hell` → `Ötti
  Hell`).
- `euro_to_cents(text: str) -> int` – `"1.2"` → 120, `"0.55"` → 55, `"144.28"` → 14428; more than
  2 decimals or junk → LegacyError.
- `PLACEHOLDER_CENTS = 1_000_000` (10.000 €): prices ≥ this become 0 and are reported.
- `@dataclass(frozen=True) ImportPlan`: `tiers: list[str]`, `groups: list[str]`,
  `persons: list[PlannedPerson(name, tier, is_hidden, is_collective)]`,
  `drinks: list[PlannedDrink(name, group, crate_size, is_hidden, is_keg, prices: dict[str,int])]`
  (prices keyed by tier name), `report: list[str]`.
- `build_plan(users_csv: str, drinks_csv: str, mapping: Mapping) -> ImportPlan` – rules from spec
  §4 and §8: role ∉ mapping.tiers ∪ {"hidden"} → error; hidden users → `hidden_tier`, is_hidden;
  `collective` names must exist; every CSV drink needs a `groups` entry; `Gruppe = hidden` → hidden
  unless listed in `kegs` (keg wins, not hidden); `kegs`/`rename`/`price_overrides` names must
  exist; groups = `group_order` (every used group must be listed); length limits checked; all
  problems collected, then one LegacyError. Drink order = CSV order (extra drinks appended).

- [ ] **Step 1: Failing tests:** `test_reads_cp1252_crlf`, `test_prettify_with_replacements_and_rename`,
  `test_euro_to_cents_exact`, `test_placeholder_price_becomes_zero_and_is_reported`,
  `test_roles_map_to_tiers_and_hidden_tier`, `test_collective_flagged`,
  `test_unknown_mapping_name_aborts` (collective, groups, kegs, rename, price_overrides each),
  `test_unknown_role_aborts`, `test_drink_without_group_aborts`, `test_keg_not_hidden`,
  `test_price_overrides_win`, `test_extra_drink_appended`, `test_too_long_name_aborts`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(server): plan a legacy import from CSV and a mapping file`.

### Task 3: Persistence + CLI – run the import

**Files:**
- Create: `server/bartab/persistence/legacy_import.py`
- Modify: `server/bartab/cli.py` (subcommand `import-legacy --users PATH --drinks PATH --mapping
  PATH [--dry-run]`)
- Test: `server/tests/persistence/test_legacy_import.py`, `server/tests/test_cli.py` (or existing
  CLI test file)

**Interfaces:**
- `class NotEmpty(Exception)`.
- `apply_plan(session, clock, plan: ImportPlan) -> None` – refuses (NotEmpty) if any price tier,
  group, person or drink exists; creates tiers (sort_order = list order), groups (sort_order,
  colour from the app's group palette order — reuse what master data uses for new groups),
  persons, drinks (sort_order within group = plan order), prices; all in the caller's
  transaction.
- CLI: reads files as bytes, builds the plan, prints `plan.report` and counts; `--dry-run` stops
  there; else applies in one session commit. Exit code 0 ok, 1 on LegacyError/NotEmpty with the
  message on stderr.

- [ ] **Step 1: Failing tests:** `test_import_creates_everything` (counts, prices, flags, order),
  `test_refuses_non_empty_database`, `test_import_is_all_or_nothing` (error mid-way → nothing
  written), CLI `--dry-run` writes nothing, CLI error exit code 1.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat(server): import legacy data from the command line`.

### Task 4: App – kegs in catalog, drink grid and admin

**Files:**
- Modify: `app/lib/data/api/dto.dart`, `app/lib/data/api/mappers.dart`,
  `app/lib/domain/catalog.dart` (Drink.isKeg; drink-selection lists exclude kegs alongside
  hidden), `app/lib/presentation/admin/drinks_screen.dart` (switch "Fass" in the drink form, sent
  as `is_keg`), `app_de.arb`
- Test: `app/test/data/api/dto_contract_test.dart`, `app/test/domain/catalog_test.dart`,
  `app/test/presentation/admin/drinks_screen_test.dart`, drink selection test

- [ ] **Step 1: Failing tests:** DTO contract with `is_keg`; catalog drink grid excludes a keg that
  is not hidden; event-booking drink list includes kegs; admin form switch "Fass" sends
  `is_keg: true`; a cached catalog without `is_keg` (older cache) reads as false.
- [ ] **Step 2–4:** FAIL → implement → `app/tool/check.sh` PASS.
- [ ] **Step 5: Commit** `feat(app): kegs as their own drink kind`.

### Task 5: App – keg price in the event booking

**Files:**
- Modify: `app/lib/presentation/admin/event_booking_screen.dart`, `app_de.arb`
- Test: `app/test/presentation/admin/event_booking_screen_test.dart`

**Behaviour:** each keg line shows a price field (euros, keypad or numeric input consistent with
the screen) pre-filled with the keg's price for the chosen person's tier (empty if none); "Buchen"
is disabled while any keg line with quantity > 0 has no price; 0,00 € allowed; the entered price
(cents) is sent as the line's unit price; changing the person re-fills only untouched price
fields. Label "Einkaufspreis".

- [ ] **Step 1: Failing tests:** pre-fill; missing price blocks booking; edited price is sent;
  0 allowed; non-keg lines unchanged.
- [ ] **Step 2–4:** FAIL → implement → `app/tool/check.sh` PASS.
- [ ] **Step 5: Commit** `feat(app): enter the purchase price for kegs in event bookings`.

### Task 6: Ops – entrypoint, healthcheck, secret key removal, operator docs

**Files:**
- Modify: `server/docker-entrypoint.sh` (`chown -R bartab:bartab /data`, failure logged and
  tolerated), `docker-compose.yml` (healthcheck on `http://localhost:8000/api/v1/health` using
  python stdlib, interval 30s), `docker-compose.override.example.yml` (variant (b) with entrypoint
  `websecure`), remove `secret_key` from `server/bartab/config.py`, `.env.example`,
  `app/tool/e2e.sh`, tests; `README.md` operator section (install on a Traefik host, update,
  `import-legacy` with a mapping file example using invented names, pairing, backup via
  `sqlite3 .backup` cron, cut-over steps from spec §7)
- Create: `docs/legacy-mapping.example.json` (invented names only)
- Test: `server/tests/test_config.py` (an old `.env` with BARTAB_SECRET_KEY still loads),
  `app/tool/e2e.sh` run

- [ ] **Step 1: Failing test** for config tolerance (already true via extra="ignore" — assert it).
- [ ] **Step 2:** implement the rest; run `server/tool/test.sh`, `app/tool/check.sh`,
  `app/tool/e2e.sh` → all PASS.
- [ ] **Step 3: Commit** `chore: production deployment ready` and `docs: operator guide`.
