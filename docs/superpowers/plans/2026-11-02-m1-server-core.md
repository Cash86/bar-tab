# Milestone 1 — Server Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tested FastAPI server that stores bar-tab master data and bookings in SQLite, authenticates tablets and the admin PIN, serves the catalog and running tabs, accepts idempotent booking batches, and ships with the repo foundation (README, licence, CLAUDE.md, Docker, CI).

**Architecture:** `server/bartab/` split into `domain/` (pure Python: stock math, clock), `persistence/` (SQLAlchemy models, Alembic, repositories), `api/` (FastAPI routers, auth dependencies, Pydantic schemas) and `cli.py`. The OpenAPI schema is exported to `api/openapi.json` at repo root as the contract the Flutter app (milestone 2) generates its DTOs from.

**Tech Stack:** Python 3.12 (in Docker), FastAPI 0.115, SQLAlchemy 2.0, Alembic 1.13, Pydantic 2 + pydantic-settings, argon2-cffi, itsdangerous, pytest 8, httpx, freezegun, ruff.

**Spec:** `docs/superpowers/specs/2026-11-02-bar-tab-design.md` (§3 domain, §5 server, §6 config, §7 repo, §8 rules). Later milestones get their own plans.

## Global Constraints

- All repo content in English; UI strings German (not in this milestone).
- Nothing club-specific or secret in the repo: no real names, no club names, no addresses, no credentials. Demo data is invented.
- All configuration via env vars with prefix `BARTAB_` (`.env`, never committed; `.env.example` is).
- IDs are UUID4 strings; every entity has `created_at` / `updated_at` (UTC, timezone-aware).
- Money is integer cents everywhere; no floats for money.
- The unit price sent with a booking is final; the server never re-prices (spec §3).
- A booking belongs to the period open when the server receives it; if `booked_at` is before that period's `started_at`, it is flagged `late` (spec §5).
- No `datetime.now()` outside `bartab/domain/clock.py`; everything takes a `Clock`.
- Every schema change ships an Alembic migration tested by `alembic upgrade head` on a fresh DB.
- TDD: write the failing test first; never weaken an existing test to get green.
- Conventional Commits; each commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `ruff check` and `ruff format --check` clean; line length 100.
- Tests run in Docker: `server/tool/test.sh [pytest args]`.

## Review Focus

1. A tablet retries a booking batch after a timeout → each booking UUID is stored exactly once and the retry reports `duplicate`, not an error. (Task 7)
2. The same UUID arrives with a different payload → rejected as `conflict`, original row untouched. (Task 7)
3. A tablet with a stale catalog books a person or drink that was deactivated meanwhile → accepted (the drink was physically taken); an id that never existed → `rejected`, other items in the batch still stored. (Task 7)
4. A mistyped quantity (0, negative, or > 999) → that item `rejected`; prices < 0 rejected. (Task 7)
5. Umlauts and ß in names ("Rüdiger", "Faßbrause") round-trip unchanged through DB and JSON — the legacy system broke on them. (Task 6)

---

## File Structure

```
LICENSE                                  MIT, holder "bar-tab contributors"
README.md                                what/why, quick start, links
CLAUDE.md                                agent rules (spec §8)
.env.example                             all BARTAB_ vars with placeholders
.github/workflows/server.yml             pytest + ruff, path filter server/**, api/**
api/openapi.json                         exported contract (generated, committed)
docker-compose.yml                       server service + ./data volume
docker-compose.override.example.yml      Traefik labels template, local port variant
server/
  pyproject.toml
  Dockerfile                             production image (uvicorn)
  Dockerfile.dev                         test image
  alembic.ini
  alembic/env.py, alembic/versions/0001_initial.py
  tool/test.sh                           build dev image if missing, run pytest in it
  tool/export_openapi.py                 writes ../api/openapi.json
  bartab/
    __init__.py
    config.py                            Settings
    main.py                              create_app(settings, clock) factory
    cli.py                               seed-demo, export-openapi
    domain/clock.py                      Clock, SystemClock, FixedClock
    domain/stock.py                      stock math
    persistence/db.py                    Base, engine, session factory
    persistence/models.py                ORM models
    persistence/repos.py                 query/write functions
    api/deps.py                          db session, clock, device auth, admin auth
    api/schemas.py                       Pydantic request/response models
    api/routes_health.py
    api/routes_admin_session.py
    api/routes_catalog.py
    api/routes_bookings.py
    security.py                          PIN hashing, admin token sign/verify, lockout
    demo_data.py                         invented seed data
  tests/
    conftest.py                          app/client/db fixtures, FixedClock
    test_config.py
    domain/test_stock.py
    persistence/test_migrations.py
    persistence/test_repos.py
    api/test_health.py
    api/test_admin_session.py
    api/test_catalog.py
    api/test_bookings.py
    api/test_tabs.py
    test_openapi_contract.py
    test_demo_seed.py
```

---

### Task 1: Repo foundation and server skeleton with health endpoint

**Files:**
- Create: `LICENSE`, `README.md`, `CLAUDE.md`, `.env.example`, `server/pyproject.toml`, `server/Dockerfile.dev`, `server/tool/test.sh`, `server/bartab/__init__.py`, `server/bartab/config.py`, `server/bartab/main.py`, `server/bartab/api/routes_health.py`, `server/bartab/domain/clock.py`
- Modify: `.gitignore` (add `data/`, `__pycache__/`, `.pytest_cache/`, `docker-compose.override.yml`)
- Test: `server/tests/conftest.py`, `server/tests/test_config.py`, `server/tests/api/test_health.py`

**Interfaces:**
- Produces:
  - `Settings` (pydantic-settings, `env_prefix="BARTAB_"`): `public_url: str`, `db_path: Path`, `data_dir: Path`, `secret_key: str` (min 32 chars), `device_keys: list[str]` (comma-separated in env, min 1, each min 32 chars), `initial_admin_pin: str | None` (4–8 digits), `tz: str = "Europe/Berlin"`, `smtp_host/smtp_port/smtp_user/smtp_password/smtp_from: str | None = None` (used in milestone 4), `monthly_report_day: int = 1`, `monthly_report_time: str = "08:00"`.
  - `Clock` protocol with `now() -> datetime` (UTC aware); `SystemClock`; `FixedClock(at: datetime)` with `advance(timedelta)`.
  - `create_app(settings: Settings, clock: Clock) -> FastAPI`.
  - `GET /api/v1/health` → `{"status": "ok"}` (no auth).
  - Test fixtures in `conftest.py`: `settings` (tmp db path, two 32-char device keys, pin `"1234"`), `clock` (`FixedClock(2026-11-02T18:00Z)`), `app`, `client` (TestClient), `device_headers` (`{"Authorization": "Bearer <first key>"}`).

- [ ] **Step 1: Write failing tests**

```python
# tests/test_config.py
def test_device_keys_are_split_from_comma_separated_env(monkeypatch, tmp_path):
    monkeypatch.setenv("BARTAB_DEVICE_KEYS", "a" * 32 + "," + "b" * 32)
    ... # set the other required vars
    assert Settings().device_keys == ["a" * 32, "b" * 32]

def test_short_device_key_is_rejected(...): pytest.raises(ValidationError) for "short"
def test_short_secret_key_is_rejected(...)

# tests/api/test_health.py
def test_health_reports_ok_without_auth(client):
    assert client.get("/api/v1/health").json() == {"status": "ok"}
```

- [ ] **Step 2: Run** `server/tool/test.sh` → FAIL (module not found).
- [ ] **Step 3: Implement** the files above. `pyproject.toml` pins: fastapi 0.115.0, uvicorn[standard] 0.30.6, sqlalchemy 2.0.35, alembic 1.13.3, pydantic 2.9.2, pydantic-settings 2.5.2, argon2-cffi 23.1.0, itsdangerous 2.2.0; dev: pytest 8.3.3, httpx 0.27.2, freezegun 1.5.1, ruff 0.6.9. `Dockerfile.dev` = `python:3.12-slim`, installs `-e .[dev]` from a stub package (source mounted at runtime). `tool/test.sh` builds `bartab-dev:latest` when absent and runs `docker run --rm -v "$PWD/server:/srv" -w /srv bartab-dev:latest pytest "$@"`, then `ruff check . && ruff format --check .`.
  - `README.md`: one-paragraph what/why, status "under construction", "Development" section with `server/tool/test.sh`, licence line. Full operator guide comes in milestone 5.
  - `CLAUDE.md`: project language rule (English repo / German chat), spec location, TDD + test-protection rules, ask-don't-invent, no secrets/real data in repo, Conventional Commits with trailer, layering for server (`domain` pure, `persistence`, `api`) and for app (`domain`/`data`/`presentation`, Riverpod, freezed, Drift, mocktail, `.arb` strings), no `now()` outside clock, migrations with every schema change. Keep under 150 lines.
  - `.env.example`: every `Settings` field with a placeholder and a one-line comment; device key hint `openssl rand -hex 32`.
- [ ] **Step 4: Run** `server/tool/test.sh` → PASS, ruff clean.
- [ ] **Step 5: Commit** `chore: add repo foundation and server skeleton with health endpoint`

---

### Task 2: Stock math (pure domain)

**Files:**
- Create: `server/bartab/domain/stock.py`
- Test: `server/tests/domain/test_stock.py`

**Interfaces:**
- Produces:
  - `@dataclass(frozen=True) DrinkStock(drink_id: str, group_id: str, opening: int, delivered: int, booked: int, counted: int | None)` with properties `expected -> int` (`opening + delivered - booked`) and `shrinkage -> int | None` (`expected - counted`, `None` when `counted is None`).
  - `group_totals(stocks: Iterable[DrinkStock]) -> dict[str, DrinkStock]` keyed by `group_id`, summing all fields (`counted` is `None` if any member is `None`); returned `drink_id` is `""`.

- [ ] **Step 1: Write failing tests** — one table test for `expected`/`shrinkage` with rows: plain (`100,40,30,105` → expected 110, shrinkage 5), no count (`shrinkage is None`), negative shrinkage (count above expected → `-3`), zero everything. Separate tests: `group_totals` sums two drinks of one group and keeps a second group apart; a group with one uncounted drink has `counted is None`.
- [ ] **Step 2: Run** `server/tool/test.sh tests/domain` → FAIL.
- [ ] **Step 3: Implement** `stock.py`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(server): add stock and shrinkage math`

---

### Task 3: Database models and initial migration

**Files:**
- Create: `server/bartab/persistence/db.py`, `server/bartab/persistence/models.py`, `server/alembic.ini`, `server/alembic/env.py`, `server/alembic/versions/0001_initial.py`
- Test: `server/tests/persistence/test_migrations.py`

**Interfaces:**
- Produces (SQLAlchemy 2.0 typed models, `Base` in `db.py`; `db.py` also: `make_engine(db_path)`, `make_session_factory(engine)`, SQLite pragmas WAL + foreign_keys):
  - `PriceTier(id, name unique, sort_order:int, created_at, updated_at)`
  - `Person(id, name, price_tier_id FK, is_hidden:bool=False, is_collective:bool=False, is_active:bool=True, created_at, updated_at)`
  - `DrinkGroup(id, name unique, sort_order:int, color:str  # "#RRGGBB", created_at, updated_at)`
  - `Drink(id, name, group_id FK, crate_size:int>=1, sort_order:int, is_hidden:bool=False, is_active:bool=True, created_at, updated_at)`
  - `DrinkPrice(drink_id FK, price_tier_id FK, price_cents:int>=0)` — composite PK
  - `Period(id, started_at, closed_at nullable, created_at, updated_at)` — at most one row with `closed_at IS NULL` (partial unique index)
  - `StockEntry(id, period_id FK, drink_id FK, kind: "opening"|"delivery"|"count", quantity:int, created_at, updated_at)` — deliveries/counts used in milestones 3–4; opening rows created here
  - `Booking(id, period_id FK, person_id FK, drink_id FK, quantity:int, unit_price_cents:int, booked_at, received_at, device_id:str, is_late:bool, created_at, updated_at)`
  - `AppSetting(key PK, value:str)` — holds `admin_pin_hash`
- Migration `0001_initial` creates exactly these tables, constraints and the partial index.

- [ ] **Step 1: Write failing tests**
  - `test_upgrade_head_creates_all_tables` — run `alembic upgrade head` on a tmp DB via `alembic.command.upgrade` with `sqlalchemy.url` pointing at it; inspector lists the nine tables.
  - `test_models_match_migration` — `alembic.autogenerate.compare_metadata(MigrationContext, Base.metadata)` returns `[]`.
  - `test_second_open_period_is_rejected` — insert two periods with `closed_at=None` → `IntegrityError`.
  - `test_negative_price_is_rejected` — CHECK constraint → `IntegrityError`.
- [ ] **Step 2: Run** `server/tool/test.sh tests/persistence` → FAIL.
- [ ] **Step 3: Implement** models and migration (hand-written, not left as raw autogenerate output).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(server): add database schema and initial migration`

---

### Task 4: Repositories and period bootstrap

**Files:**
- Create: `server/bartab/persistence/repos.py`
- Test: `server/tests/persistence/test_repos.py`

**Interfaces:**
- Consumes: models (Task 3), `Clock` (Task 1).
- Produces (functions taking `session: Session`, flush but do not commit):
  - `ensure_open_period(session, clock) -> Period` — returns the open period; creates one with `started_at=clock.now()` if none exists.
  - `get_catalog(session) -> Catalog` — dataclass with `price_tiers`, `persons`, `groups`, `drinks` (each drink with `prices: dict[tier_id, cents]`), all ordered by `sort_order` then `name`; includes inactive and hidden rows (the app filters).
  - `get_booking(session, booking_id) -> Booking | None`
  - `add_booking(session, *, id, person_id, drink_id, quantity, unit_price_cents, booked_at, device_id, clock) -> Booking` — sets `period_id` to the open period, `received_at=clock.now()`, `is_late = booked_at < period.started_at`.
  - `tabs_for_open_period(session) -> dict[str, int]` — person_id → sum of `quantity * unit_price_cents`, only persons with bookings.
  - `get_setting(session, key) -> str | None`, `set_setting(session, key, value) -> None`.

- [ ] **Step 1: Write failing tests**
  - `ensure_open_period` creates once and returns the same row on the second call.
  - `add_booking` assigns the open period and `is_late=False` for `booked_at` after `started_at`; `is_late=True` for `booked_at` one minute before.
  - `tabs_for_open_period`: person A 2×60 + 1×130 → 250; person B absent; bookings of a closed period excluded (close it by setting `closed_at`, open a new one).
  - `get_catalog` orders drinks by `sort_order` then `name` and exposes prices per tier.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(server): add repositories and open-period bootstrap`

---

### Task 5: Device auth, admin PIN and admin session

**Files:**
- Create: `server/bartab/security.py`, `server/bartab/api/deps.py`, `server/bartab/api/routes_admin_session.py`, `server/bartab/api/schemas.py` (start)
- Modify: `server/bartab/main.py` (mount router, seed PIN on startup)
- Test: `server/tests/api/test_admin_session.py`

**Interfaces:**
- Consumes: `Settings`, `Clock`, `get_setting/set_setting`.
- Produces:
  - `hash_pin(pin: str) -> str`, `verify_pin(pin: str, hashed: str) -> bool` (argon2).
  - `seed_admin_pin(session, settings) -> None` — when `admin_pin_hash` is unset and `initial_admin_pin` is set, store its hash; never overwrites an existing hash. Called from app startup.
  - `PinLockout(max_failures=5, lock_seconds=60, clock)` — in-memory per device; `check(device_id) -> None` raises `LockedOut(retry_after: int)`; `record_failure(device_id)`; `reset(device_id)`.
  - Dependency `require_device(authorization header) -> str` returning a device id = first 8 hex chars of `sha256(key)`; missing/unknown key → 401 `{"detail": "invalid_device_key"}`. Compare with `hmac.compare_digest`.
  - Dependency `require_admin(X-Admin-Token header, device) -> None`; invalid/expired → 401 `{"detail": "admin_session_required"}`.
  - `POST /api/v1/admin/session` body `{"pin": str}` (device auth) → 200 `{"token": str, "expires_in": 900}`; wrong PIN → 401 `{"detail": "wrong_pin"}`; locked → 429 `{"detail": "locked", "retry_after": n}`. Token = itsdangerous `TimestampSigner(settings.secret_key)` over the device id, max age 900 s (the tablet's 2-minute idle logout is app-side).
  - `GET /api/v1/admin/ping` (admin) → 204 — exists so later admin routes have a tested guard.

- [ ] **Step 1: Write failing tests**
  - health works without key; `GET /api/v1/admin/ping` without device key → 401 `invalid_device_key`; with device key but no admin token → 401 `admin_session_required`.
  - correct PIN `"1234"` → 200 with token; ping with that token → 204.
  - token after `clock.advance(901 s)` → 401 (use freezegun or a signer fed by the clock — the signer's time source must be the injected clock).
  - five wrong PINs → sixth attempt (even correct) → 429 with `retry_after == 60`; after `advance(61 s)` the correct PIN works.
  - lockout is per device: device B can still log in while A is locked.
  - `seed_admin_pin` does not overwrite an existing hash (set hash of "9999", seed with "1234", "9999" still verifies).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(server): add device keys, admin PIN and admin sessions`

---

### Task 6: Catalog endpoint

**Files:**
- Create: `server/bartab/api/routes_catalog.py`
- Modify: `server/bartab/api/schemas.py`, `server/bartab/main.py`
- Test: `server/tests/api/test_catalog.py`

**Interfaces:**
- Consumes: `get_catalog`, `require_device`.
- Produces: `GET /api/v1/catalog` (device auth) →
  ```json
  {"price_tiers":[{"id","name","sort_order"}],
   "persons":[{"id","name","price_tier_id","is_hidden","is_collective","is_active"}],
   "groups":[{"id","name","sort_order","color"}],
   "drinks":[{"id","name","group_id","crate_size","sort_order","is_hidden","is_active","prices":{"<tier_id>":cents}}],
   "etag":"<sha256 of the canonical JSON body>"}
  ```
  Response header `ETag` equals `etag`; request with matching `If-None-Match` → 304 with empty body.

- [ ] **Step 1: Write failing tests**
  - requires device key (401 without).
  - returns seeded tiers/persons/groups/drinks with prices keyed by tier id.
  - **Review Focus 5:** persons "Rüdiger" and "Faßbrause" come back byte-identical; response is `application/json` UTF-8.
  - second request with `If-None-Match: <etag>` → 304; after renaming a drink the etag changes and → 200.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(server): add catalog endpoint with etag`

---

### Task 7: Booking batch endpoint (idempotent)

**Files:**
- Create: `server/bartab/api/routes_bookings.py`
- Modify: `server/bartab/api/schemas.py`, `server/bartab/main.py`
- Test: `server/tests/api/test_bookings.py`

**Interfaces:**
- Consumes: `add_booking`, `get_booking`, `require_device`.
- Produces: `POST /api/v1/bookings` (device auth), body
  `{"bookings":[{"id":uuid,"person_id","drink_id","quantity":int,"unit_price_cents":int,"booked_at":iso8601-with-offset}]}` (1–200 items) →
  200 `{"results":[{"id", "status": "accepted"|"duplicate"|"conflict"|"rejected", "reason": str|null}]}` in request order. Per-item, one transaction per item so a bad item never drops good ones.
  - `accepted`: stored.
  - `duplicate`: same id exists with identical person/drink/quantity/price/booked_at.
  - `conflict`: same id exists with any field different; stored row unchanged.
  - `rejected` reasons: `unknown_person`, `unknown_drink`, `invalid_quantity` (not 1..999), `invalid_price` (< 0).
  - Inactive or hidden person/drink → `accepted` (Review Focus 3).

- [ ] **Step 1: Write failing tests** (one claim each)
  - accepted booking is stored with `device_id` of the caller and the open period.
  - **RF1:** posting the same batch twice → second response all `duplicate`; DB row count unchanged.
  - **RF2:** same id with quantity 2 instead of 1 → `conflict`; stored quantity still 1.
  - **RF3:** batch [valid, unknown person, valid] → `accepted, rejected(unknown_person), accepted`; two rows stored. Deactivated drink → `accepted`.
  - **RF4:** table test over quantity 0, -1, 1000 → `rejected(invalid_quantity)`; quantity 999 → accepted; price -1 → `rejected(invalid_price)`.
  - `booked_at` before the open period's `started_at` → stored with `is_late=True`.
  - empty list or 201 items → 422.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(server): add idempotent booking batch endpoint`

---

### Task 8: Tabs endpoint

**Files:**
- Modify: `server/bartab/api/routes_bookings.py`, `server/bartab/api/schemas.py`
- Test: `server/tests/api/test_tabs.py`

**Interfaces:**
- Produces: `GET /api/v1/tabs` (device auth) → `{"period_started_at": iso, "tabs": {"<person_id>": cents}}` for the open period.

- [ ] **Step 1: Write failing tests** — totals after posting bookings for two persons; person without bookings absent; requires device key.
- [ ] **Step 2–4:** FAIL → implement via `tabs_for_open_period` → PASS.
- [ ] **Step 5: Commit** `feat(server): add running tabs endpoint`

---

### Task 9: Demo seed CLI and OpenAPI contract

**Files:**
- Create: `server/bartab/demo_data.py`, `server/bartab/cli.py`, `server/tool/export_openapi.py`, `api/openapi.json`
- Test: `server/tests/test_demo_seed.py`, `server/tests/test_openapi_contract.py`

**Interfaces:**
- Produces:
  - `python -m bartab.cli seed-demo` — on an empty DB only (refuses with exit code 1 otherwise): tiers "Mitglieder" and "Gäste"; groups Bier (#E3A33A), Alkoholfrei (#9CC46A), Limo (#C79BF0), Wasser (#72B8DE); ~10 invented drinks with prices for both tiers, crate sizes 20/24/12, one hidden keg (crate size 1); ~12 invented persons incl. one collective ("Stammtisch") and one hidden ("Veranstaltung"), at least one name with an umlaut. All names invented and generic.
  - `python -m bartab.cli export-openapi PATH` and `tool/export_openapi.py` write `app.openapi()` as pretty JSON (sorted keys, trailing newline).

- [ ] **Step 1: Write failing tests**
  - seed on empty DB creates the counts above and an open period; second run exits 1 and changes nothing.
  - `test_committed_openapi_matches_app` — generated JSON equals `../api/openapi.json`; failure message tells to run `server/tool/export_openapi.py`.
- [ ] **Step 2–4:** FAIL → implement, run export once → PASS.
- [ ] **Step 5: Commit** `feat(server): add demo seed and exported OpenAPI contract`

---

### Task 10: Production image, compose and CI

**Files:**
- Create: `server/Dockerfile`, `docker-compose.yml`, `docker-compose.override.example.yml`, `.github/workflows/server.yml`
- Modify: `README.md` (quick start: copy `.env.example`, `docker compose up -d`, `docker compose exec server alembic upgrade head`, optional `seed-demo`, open `/api/v1/health`)

**Interfaces:**
- Produces: image runs `alembic upgrade head` then `uvicorn bartab.main:app_from_env --host 0.0.0.0 --port 8000` (add `app_from_env()` to `main.py` building `Settings()` + `SystemClock()`); data in `/data`. Compose service `server`, volume `./data:/data`, `env_file: .env`, networks `proxy` (external) in the override example only — base compose works stand-alone with port `8000` exposed via the override example's local variant. CI: on `pull_request` and `push` to `main` with `paths: [server/**, api/**, .github/workflows/server.yml]`, job runs `pip install -e server[dev]`, `pytest`, `ruff check`, `ruff format --check` on Python 3.12.

- [ ] **Step 1: Verify image build** `docker compose build` → succeeds.
- [ ] **Step 2: Smoke run** with a throwaway `.env` from `.env.example` (generated keys): `docker compose up -d`, `curl -fsS localhost:8000/api/v1/health` → `{"status":"ok"}`; `docker compose down`. Delete the throwaway `.env`.
- [ ] **Step 3: Secret scan** `git grep -nIiE "password=|secret=|BEGIN .*KEY|@gmail" -- . ':!*.example'` → no hits.
- [ ] **Step 4: Full suite** `server/tool/test.sh` → all PASS, ruff clean.
- [ ] **Step 5: Commit** `chore: add production image, compose setup and server CI`
