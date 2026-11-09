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
# Edit .env: set BARTAB_PUBLIC_URL, BARTAB_INITIAL_ADMIN_PIN and BARTAB_DEVICE_KEYS.
openssl rand -hex 32   # run once per entry of BARTAB_DEVICE_KEYS
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

Copy `.env.example` to `.env` and adjust it for local runs.

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

## Operator guide

### Install (host with Traefik)

Requires Docker with Compose and a running Traefik with an external Docker network `proxy`, an
entrypoint `websecure` and a certificate resolver.

```sh
git clone <repository-url> /opt/containers/bar-tab && cd /opt/containers/bar-tab
cp .env.example .env                 # set BARTAB_PUBLIC_URL=https://bar.example.org, admin PIN, keys
openssl rand -hex 32                 # once per tablet, comma-separated in BARTAB_DEVICE_KEYS
cp docker-compose.override.example.yml docker-compose.override.yml
# keep variant (b): remove the `ports` block and uncomment the Traefik labels and networks;
# set the host rule, <your-certresolver> and (optionally) <your-middlewares>
docker compose up -d --build
docker compose ps                    # wait until the server shows "healthy"
```

The compose healthcheck calls `/api/v1/health`; Traefik only routes to healthy containers.
Migrations run on container start. The container fixes ownership of `./data` itself.

### Update

```sh
git pull --ff-only
docker compose up -d --build
docker compose ps
```

### Import legacy data

Only into an empty database, with the server running. Put the legacy CSV files and your mapping file (see
[docs/legacy-mapping.example.json](docs/legacy-mapping.example.json) for every key) under
`./data/import/`; `./data` is mounted as `/data` in the container. Keep these files out of git.

```sh
docker compose exec server python -m bartab.cli import-legacy \
  --users /data/import/user.csv --drinks /data/import/drink.csv \
  --mapping /data/import/mapping.json --dry-run     # prints the report, writes nothing
# if the report looks right, run again without --dry-run
```

The import is strict: any unknown role, unmapped drink or unmatched name aborts with a message
and writes nothing.

### Pairing the tablet

See [Tablet](#tablet): enter `https://bar.example.org` and one key from `BARTAB_DEVICE_KEYS`.
An already paired tablet is re-paired in the admin area ("Server neu koppeln").

### Backup

Take a consistent snapshot of the SQLite database, for example daily from cron on the host
(needs `sqlite3` installed on the host; `%` must be escaped in crontab). `data/` is owned by
uid 10001 after the container's chown, so run the cron job as root:

```cron
0 3 * * * sqlite3 /opt/containers/bar-tab/data/bartab.db ".backup '/opt/backup/bartab-$(date +\%F).db'"
```

Without host `sqlite3`, use the Python module inside the container:

```sh
docker compose exec server python -c "import sqlite3; s=sqlite3.connect('/data/bartab.db'); d=sqlite3.connect('/data/backup.db'); s.backup(d)"
```

Copy the backups off the machine. A restore is: stop the server, replace `data/bartab.db`, start.

### Cut-over from the paper/legacy system

1. Deploy, then run the import (dry run first) with the local mapping file.
2. Log in to the admin area with `BARTAB_INITIAL_ADMIN_PIN` and change the PIN (Admin, "Admin-PIN ändern").
3. Re-pair the tablet: admin area, "Server neu koppeln" (or clear the app data and pair on first
   start; only when no bookings are queued).
4. Enter the opening count, then start normal operation.

## Settlement and reports (operator notes)

- **Mail:** set `BARTAB_SMTP_HOST`, `_PORT`, `_USER`, `_PASSWORD` and `_FROM`. Port 465 uses
  implicit TLS; other ports (typically 587) use STARTTLS. Without SMTP settings or recipients
  nothing is sent and the settlement reports the mail as skipped.
- **Monthly report:** `BARTAB_MONTHLY_REPORT_DAY` (1-28) and `BARTAB_MONTHLY_REPORT_TIME`
  (`HH:MM`, server timezone). Invalid values stop the server at startup. Failed or missed sends
  are retried hourly until the end of the month.
- **Settlement:** in the admin area, choose the settlement, count the stock per drink, check the
  review and confirm. The PDF is mailed to the recipients; the counts become the next opening
  stock.
- **First settlement:** enter an opening count first (admin area), otherwise the opening stock
  is zero.
- **Recipients, valuation tier and re-send:** in the admin area under "Einstellungen"; the last
  settlement PDF can be sent again there.

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
device key. Use one of the keys listed in `BARTAB_DEVICE_KEYS` in the server's `.env`. The server
URL and the device key are kept in app-private storage (the app's local database, protected by the
Android app sandbox, not the hardware keystore, which is unreliable on some tablets). The device key
is a per-tablet secret: if a tablet is lost, revoke its key on the server (remove it from
`BARTAB_DEVICE_KEYS`).

**Kiosk mode.** The app locks to landscape, hides the system bars and keeps the screen on. To
stop members from leaving it, enable Android screen pinning (Settings → Security → App
pinning), then open the app and pin it from the recent-apps view.

**Screensaver.** After 2 minutes without a touch on the name list, the app dims to a black
screen with a small, slowly moving hint and lowers the brightness (the screen stays on, so
there is no Android lock screen). The first touch only wakes it and is not passed on.

**Queued bookings and data loss.** Bookings made while the server is unreachable live only in
the tablet's local database until they are synced. Never "clear app data" and never uninstall the
app while bookings are queued (the sync indicator on the name list shows the count): they would be
lost for good. If the server rejects the device key (key revoked or changed), fix the key on the
server side (`BARTAB_DEVICE_KEYS`); do not reinstall the app. The tablet can also be re-paired with
a new server URL or key from inside the app (admin area, "Server neu koppeln"); queued
bookings are kept.

### Hands-on test (debug build)

To try a debug build against a server on your own machine:

1. Copy `docker-compose.override.example.yml` to `docker-compose.override.yml`, keep variant (a)
   (published port 8000), then `docker compose up -d --build`.
2. Connect the tablet by USB and run `adb reverse tcp:8000 tcp:8000`, so `localhost` on the
   tablet reaches the server.
3. Start the debug build (`cd app && flutter run`, or install the debug APK).
4. On first start enter the URL `http://localhost:8000` and one device key from
   `BARTAB_DEVICE_KEYS` in `.env`. Tip: `adb shell input text <key>` types the key into the
   focused field.


## Licence

MIT, see [LICENSE](LICENSE).
