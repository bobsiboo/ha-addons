#!/bin/sh
set -e

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

OPTS="/data/options.json"

# Read options safely (jq is installed in the Dockerfile)
TZ_OPT="$(jq -r '.tz // "UTC"' "$OPTS")"
BASE_URL="$(jq -r '.base_url // empty' "$OPTS")"
ALLOW_SIGNUP="$(jq -r '.allow_signup // true' "$OPTS")"

DEF_EMAIL="$(jq -r '.default_email // "changeme@example.com"' "$OPTS")"
DEF_PASSWORD="$(jq -r '.default_password // "MyPassword"' "$OPTS")"
DEF_GROUP="$(jq -r '.default_group // "Home"' "$OPTS")"
DEF_HOUSEHOLD="$(jq -r '.default_household // "Home"' "$OPTS")"

API_PORT="$(jq -r '.api_port // 9000' "$OPTS")"
PUID="$(jq -r '.puid // 0' "$OPTS")"
PGID="$(jq -r '.pgid // 0' "$OPTS")"

DB_ENGINE="$(jq -r '.db_engine // "sqlite"' "$OPTS")"
PG_HOST="$(jq -r '.postgres.host // empty' "$OPTS")"
PG_PORT="$(jq -r '.postgres.port // 5432' "$OPTS")"
PG_USER="$(jq -r '.postgres.user // empty' "$OPTS")"
PG_PASS="$(jq -r '.postgres.password // empty' "$OPTS")"
PG_DB="$(jq -r '.postgres.db // "mealie"' "$OPTS")"

# Ensure Mealie's data path exists and link it into the app dir
mkdir -p /data/mealie
mkdir -p /app

if [ ! -L /app/data ]; then
  # If upstream created a real dir, migrate any contents, then replace with symlink
  if [ -d /app/data ]; then
    mv /app/data/* /data/mealie/ 2>/dev/null || true
    rmdir /app/data 2>/dev/null || true
  fi
  ln -s /data/mealie /app/data
fi


# Export env vars Mealie understands (per docs)
export TZ="${TZ_OPT}"
[ -n "$BASE_URL" ] && export BASE_URL="$BASE_URL"
export ALLOW_SIGNUP="$ALLOW_SIGNUP"
export API_PORT="$API_PORT"
# PUID/PGID (if used by image)
[ "$PUID" -ne 0 ] && export PUID="$PUID" || true
[ "$PGID" -ne 0 ] && export PGID="$PGID" || true

# Default admin bootstrap (docs checklist)
export DEFAULT_EMAIL="$DEF_EMAIL"
export DEFAULT_PASSWORD="$DEF_PASSWORD"
export DEFAULT_GROUP="$DEF_GROUP"
export DEFAULT_HOUSEHOLD="$DEF_HOUSEHOLD"

# Database config
export DB_ENGINE="$DB_ENGINE"
if [ "$DB_ENGINE" = "postgres" ]; then
  export POSTGRES_SERVER="${PG_HOST}"
  export POSTGRES_PORT="${PG_PORT}"
  export POSTGRES_USER="${PG_USER}"
  export POSTGRES_PASSWORD="${PG_PASS}"
  export POSTGRES_DB="${PG_DB}"
fi

log "==== Mealie add-on start ===="
log "Data dir -> /data/mealie  (symlinked to /app/data)"
log "Engine   -> ${DB_ENGINE}"
log "Allow signup -> ${ALLOW_SIGNUP}"
[ -n "$BASE_URL" ] && log "Base URL -> ${BASE_URL}"

# Try common upstream entrypoints, then fall back to uvicorn
if [ -x /app/run.sh ]; then
  exec /app/run.sh
elif [ -x /entrypoint.sh ]; then
  exec /entrypoint.sh
else
  # Fallback: start Mealie via uvicorn
  exec uvicorn mealie.app:app --host 0.0.0.0 --port "${API_PORT}"
fi
