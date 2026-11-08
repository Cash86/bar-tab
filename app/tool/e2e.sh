#!/usr/bin/env bash
# End-to-end sync test: starts the real server in Docker (throwaway config,
# demo data, port 18080), runs app/test_e2e against it, always cleans up.
# Needs Docker, openssl and curl. Not part of check.sh.
set -euo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(dirname "$app_dir")"
port=18080
base_url="http://localhost:${port}"

umask 077
tmp="$(mktemp -d)"
e2e_image="bartab-e2e-server:local"
compose=(docker compose -p bartab-e2e --project-directory "$tmp"
  -f "$repo_dir/docker-compose.yml" -f "$tmp/override.yml"
  --env-file "$tmp/.env")

# Installed right after mktemp: tolerates partially created state.
cleanup() {
  status=$?
  set +e
  echo "== cleanup"
  if [ -f "$tmp/override.yml" ] && [ -f "$tmp/.env" ]; then
    "${compose[@]}" down -v --remove-orphans >/dev/null ||
      echo "WARNING: docker compose down failed; check 'docker ps -a' for bartab-e2e" >&2
  fi
  # Only the e2e image; the developer's bartab-server:latest is untouched.
  docker rmi "$e2e_image" >/dev/null 2>&1
  # The data dir is created root-owned by Docker.
  rm -rf "$tmp" 2>/dev/null
  if [ -e "$tmp" ]; then
    docker run --rm -v "$tmp:/t" alpine sh -c 'rm -rf /t/* /t/.[!.]*' >/dev/null 2>&1
    rm -rf "$tmp"
  fi
  exit "$status"
}
trap cleanup EXIT

device_key="$(openssl rand -hex 32)"
device_key2="$(openssl rand -hex 32)"

cat > "$tmp/.env" <<ENV
BARTAB_SECRET_KEY=$(openssl rand -hex 32)
BARTAB_DEVICE_KEYS=${device_key},${device_key2}
BARTAB_INITIAL_ADMIN_PIN=4711
BARTAB_PUBLIC_URL=${base_url}
ENV

# --project-directory makes env_file (.env) and the ./data volume resolve
# inside the temp dir; the build context must point back at the repo.
cat > "$tmp/override.yml" <<YML
services:
  server:
    image: ${e2e_image}
    build:
      context: ${repo_dir}/server
    ports:
      - "${port}:8000"
YML

echo "== starting server"
"${compose[@]}" up -d --build

echo "== waiting for ${base_url}/api/v1/health"
ready=0
for _ in $(seq 1 60); do
  if curl -fsS -m 2 -o /dev/null "${base_url}/api/v1/health" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "Server did not become healthy within 60 s" >&2
  "${compose[@]}" logs --tail 50 server >&2 || true
  exit 1
fi

echo "== seeding demo data"
"${compose[@]}" exec -T server python -m bartab.cli seed-demo

echo "== running e2e test"
cd "$app_dir"
# One file at a time: the PIN test briefly changes the shared admin PIN.
flutter test test_e2e --concurrency=1 \
  --dart-define=E2E_BASE_URL="$base_url" \
  --dart-define=E2E_DEVICE_KEY="$device_key" \
  --dart-define=E2E_DEVICE_KEY2="$device_key2" \
  --dart-define=E2E_ADMIN_PIN=4711
