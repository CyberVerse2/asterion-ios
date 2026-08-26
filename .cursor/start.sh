#!/usr/bin/env bash
# Per-boot reconciliation for the Asterion backend services.
# Starts the local PostgreSQL and Redis daemons, ensures the databases exist,
# and applies the schemas. Idempotent and tolerant of restarts, then returns so
# the long-running service processes can start in their terminals.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Redis
if ! redis-cli ping >/dev/null 2>&1; then
  sudo redis-server --daemonize yes
fi
for _ in $(seq 1 20); do
  redis-cli ping >/dev/null 2>&1 && break
  sleep 0.5
done

# PostgreSQL (Debian/Ubuntu cluster tooling)
PG_VER="$(pg_lsclusters -h 2>/dev/null | awk 'NR==1{print $1}')"
PG_VER="${PG_VER:-16}"
sudo pg_ctlcluster "$PG_VER" main start 2>/dev/null || true
for _ in $(seq 1 30); do
  pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1 && break
  sleep 0.5
done

# Ensure the local dev role password and databases match the checked-in env.
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';" >/dev/null
for db in asterion movies; do
  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1; then
    sudo -u postgres createdb "$db"
  fi
done

# core-api user tables (Drizzle). Only push into an uninitialized database:
# drizzle-kit push reconciles the DB to the Drizzle schema and would DROP the
# `novels`/`chapters` content tables, which the API creates at runtime outside
# Drizzle. Once the schema exists it persists in the data directory, so a normal
# boot must not re-push.
if [ "$(sudo -u postgres psql -d asterion -tAc "SELECT to_regclass('public.users') IS NOT NULL")" != "t" ]; then
  ( cd services/core-api && [ -f .env ] || cp .env.example .env; npm run db:push )
fi

# Movies catalog schema is guarded with IF NOT EXISTS, so it is safe every boot.
PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres -d movies \
  -f services/movies/schema.sql >/dev/null

echo "start.sh complete: postgres + redis ready, schemas applied"
