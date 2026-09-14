#!/usr/bin/env bash
# Idempotent dependency setup for the Asterion backend services.
# Runs after the repository is checked out. Prepares source-derived state only
# (system daemons and schema live in start.sh). Safe to run repeatedly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# System packages the services need to run on Linux. Guarded so the common
# snapshot-backed build (packages already present) skips apt entirely and does
# not depend on network or sudo.
need_pkgs=()
command -v psql >/dev/null 2>&1 || need_pkgs+=(postgresql postgresql-contrib)
command -v redis-server >/dev/null 2>&1 || need_pkgs+=(redis-server)
python3 -c 'import ensurepip' >/dev/null 2>&1 || need_pkgs+=(python3-venv)
if [ "${#need_pkgs[@]}" -gt 0 ]; then
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${need_pkgs[@]}"
fi

# core-api (Node / Fastify / Drizzle)
pushd services/core-api >/dev/null
npm install
[ -f .env ] || cp .env.example .env
popd >/dev/null

# Flask scraper services (anime, movies, football)
for svc in anime movies football; do
  pushd "services/$svc" >/dev/null
  python3 -m venv .venv
  ./.venv/bin/pip install --upgrade pip
  ./.venv/bin/pip install -r requirements.txt
  popd >/dev/null
done

# Bring up the datastores and apply schemas once, so the build baseline ships an
# initialized database. Reuses start.sh, which only runs the (destructive)
# drizzle-kit push when the database is still uninitialized.
bash "$REPO_ROOT/.cursor/start.sh"

echo "install.sh complete"
