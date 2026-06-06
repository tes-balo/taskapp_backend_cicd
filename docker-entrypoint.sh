#!/bin/sh
# TaskApp Backend container entrypoint.
#
# Responsibilities:
#   1. Apply database migrations (alembic upgrade head) before the app boots.
#   2. exec the CMD (gunicorn) as PID 1 so signals (SIGTERM on `docker stop`)
#      reach gunicorn directly for a clean shutdown.
#
# TEACHING NOTE: running migrations in the entrypoint is fine for a SINGLE
# replica (our all-in-one stack). If you ever scale the backend to multiple
# replicas, run migrations as a separate one-shot job instead, or the replicas
# will race each other on `alembic upgrade head`.

set -e

echo "[entrypoint] Applying database migrations (alembic upgrade head)..."

# Retry so a slightly-slow Postgres start doesn't crash the container. In
# Compose we already gate on `depends_on: condition: service_healthy`, but this
# makes the image robust on its own too.
attempt=0
max_attempts=10
until alembic upgrade head; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "[entrypoint] ERROR: migrations failed after ${attempt} attempts." >&2
    exit 1
  fi
  echo "[entrypoint] Database not ready yet — retry ${attempt}/${max_attempts} in 3s..."
  sleep 3
done

echo "[entrypoint] Migrations complete. Starting: $*"
exec "$@"
