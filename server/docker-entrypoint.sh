#!/bin/sh
set -e
# A fresh ./data bind mount is created root-owned by Docker: fix ownership, then drop root.
if [ "$(id -u)" = "0" ]; then
  chown bartab:bartab /data
  exec setpriv --reuid=bartab --regid=bartab --init-groups "$0" "$@"
fi
# set -e aborts the container if the migration fails.
alembic upgrade head
# Exactly one worker: the admin-PIN lockout state is in-memory per process.
exec uvicorn --factory bartab.main:app_from_env --host 0.0.0.0 --port 8000 --workers 1
