#!/usr/bin/env bash
# Runs pytest, ruff check and ruff format --check inside the dev image.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE=bartab-dev:latest
# Rebuild when the dependencies or the image definition changed (sha256 kept as an image label).
HASH="$(cat "$ROOT/server/pyproject.toml" "$ROOT/server/Dockerfile.dev" | sha256sum | cut -d' ' -f1)"
if [ "$(docker image inspect -f '{{ index .Config.Labels "bartab.deps" }}' "$IMAGE" 2>/dev/null)" != "$HASH" ]; then
  docker build --label "bartab.deps=$HASH" -t "$IMAGE" -f "$ROOT/server/Dockerfile.dev" "$ROOT/server"
fi
docker run --rm --user "$(id -u):$(id -g)" \
  -e PYTHONDONTWRITEBYTECODE=1 -e HOME=/tmp -e RUFF_CACHE_DIR=/tmp/ruff \
  -v "$ROOT:/repo" -w /repo/server "$IMAGE" \
  sh -c 'pytest -p no:cacheprovider "$@" && ruff check . && ruff format --check .' sh "$@"
