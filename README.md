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

An end-to-end sync test runs the real app sync code against the real server in Docker (throwaway
config and demo data, port 18080, everything removed afterwards). It needs Docker, `openssl` and
`curl`, is not part of `check.sh`/CI, and should be run locally before merging a milestone:

```sh
app/tool/e2e.sh
```

## Licence

MIT, see [LICENSE](LICENSE).

## Tablet

The tablet app is sideloaded; it is not distributed through an app store.

**Build.** The release APK is built by the maintainer, from `app/`:

```sh
flutter build apk --release
```

The result is `app/build/app/outputs/flutter-apk/app-release.apk`. Release builds only talk
to the server over HTTPS, so `BARTAB_PUBLIC_URL` must be an `https://` URL. Debug builds
additionally allow plain HTTP to `10.0.2.2`, `localhost` and `127.0.0.1` for local development.

**Install.** Enable USB debugging on the tablet and run:

```sh
adb install -r app/build/app/outputs/flutter-apk/app-release.apk
```

**First start.** The app asks for the server URL (for example `https://bar.example.org`) and a
device key. Use one of the keys listed in `BARTAB_DEVICE_KEYS` in the server's `.env`.

**Kiosk mode.** The app locks to landscape, hides the system bars and keeps the screen on. To
stop members from leaving it, enable Android screen pinning (Settings → Security → App
pinning), then open the app and pin it from the recent-apps view.

**Screensaver.** After 2 minutes without a touch on the name list, the app dims to a black
screen with a small, slowly moving hint and lowers the brightness (the screen stays on, so
there is no Android lock screen). The first touch only wakes it and is not passed on.
