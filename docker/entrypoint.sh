#!/bin/sh
set -eu
cd /host

echo "[demo] waiting for postgres..."
until pg_isready -h db -p 5432 -U escalated >/dev/null 2>&1; do sleep 1; done

echo "[demo] ecto.create + migrate"
mix ecto.create 2>&1 || echo "[demo] ecto.create skipped"
mix ecto.migrate 2>&1 || echo "[demo] ecto.migrate skipped"

echo "[demo] ready"
exec "$@"
