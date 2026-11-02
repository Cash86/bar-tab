# bar-tab

bar-tab is a self-hosted tab ("Strichliste") for small clubs and associations: members
or bar staff book drinks on a shared tablet, and the server keeps the running tabs,
closes billing periods and sends monthly reports. It replaces paper lists with a simple,
offline-tolerant tablet app (Flutter) backed by a small Python service (FastAPI).

**Status:** under construction. Not usable yet.

## Quick start

Requires Docker with Compose.

```sh
cp .env.example .env
# Edit .env: set BARTAB_PUBLIC_URL, BARTAB_INITIAL_ADMIN_PIN and the keys below.
openssl rand -hex 32   # run once per key: BARTAB_SECRET_KEY and each entry of BARTAB_DEVICE_KEYS
cp docker-compose.override.example.yml docker-compose.override.yml  # pick the local or Traefik variant
docker compose up -d
docker compose exec server alembic upgrade head   # optional, the container already migrates on start
docker compose exec server python -m bartab.cli seed-demo   # optional demo data
```

Then open `http://localhost:8000/api/v1/health` (local variant); it returns `{"status":"ok"}`.

The placeholders in `.env.example` (such as `<generate>`) intentionally fail validation, so the
server refuses to start until you replace them. Data lives in `./data` (mounted as `/data`).
The server runs a single worker on purpose, as the admin-PIN lockout is kept in memory.

## Development

Server tests, lint and format check run in Docker:

```sh
server/tool/test.sh            # pytest, ruff check, ruff format --check
server/tool/test.sh -k health  # extra arguments are passed to pytest
```

Copy `.env.example` to `.env` and adjust it for local runs. A full operator guide will follow.

### App

The Flutter tablet app lives in `app/` (Flutter 3.44.8, landscape tablet). One command runs
dependencies, code generation, l10n, analysis, format check and tests:

```sh
app/tool/check.sh
```

Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/app_localizations*.dart`) are not committed.

## Licence

MIT, see [LICENSE](LICENSE).
