#!/usr/bin/env bash
# Runs pytest, ruff check and ruff format --check inside the dev image.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE=bartab-dev:latest
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build -t "$IMAGE" -f "$ROOT/server/Dockerfile.dev" "$ROOT/server"
fi
docker run --rm --user "$(id -u):$(id -g)" \
  -e PYTHONDONTWRITEBYTECODE=1 -e HOME=/tmp -e RUFF_CACHE_DIR=/tmp/ruff \
  -v "$ROOT:/repo" -w /repo/server "$IMAGE" \
  sh -c 'pytest -p no:cacheprovider "$@" && ruff check . && ruff format --check .' sh "$@"
