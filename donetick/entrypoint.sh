#!/bin/sh
set -e

OPTS="/data/options.json"
CONF_DIR="/config"
CONF_FILE="${CONF_DIR}/selfhosted.yaml"

# Read HA add-on options
SQLITE_PATH="$(jq -r '.sqlite_path' "$OPTS")"
JWT_SECRET_OPT="$(jq -r '.jwt_secret // empty' "$OPTS")"
SERVE_FRONTEND="$(jq -r '.serve_frontend' "$OPTS")"
REALTIME_ENABLED="$(jq -r '.realtime_enabled' "$OPTS")"
REALTIME_MAX_CONN="$(jq -r '.realtime_max_connections' "$OPTS")"

# Fallbacks/sanitization
[ -z "$REALTIME_MAX_CONN" ] || [ "$REALTIME_MAX_CONN" -le 0 ] && REALTIME_MAX_CONN=64
[ "$SERVE_FRONTEND" != "true" ] && [ "$SERVE_FRONTEND" != "false" ] && SERVE_FRONTEND=true
[ "$REALTIME_ENABLED" != "true" ] && [ "$REALTIME_ENABLED" != "false" ] && REALTIME_ENABLED=true

# Reuse existing secret if present and user left jwt_secret blank
EXISTING_SECRET=""
if [ -f "$CONF_FILE" ]; then
  EXISTING_SECRET="$(sed -n 's/^[[:space:]]*secret:[[:space:]]*\"\?\([^\"\r\n]\+\)\"\?/\1/p' "$CONF_FILE" | head -n1)"
fi

JWT_SECRET="$JWT_SECRET_OPT"
if [ -z "$JWT_SECRET" ] || [ ${#JWT_SECRET} -lt 32 ]; then
  if [ -n "$EXISTING_SECRET" ] && [ ${#EXISTING_SECRET} -ge 32 ]; then
    JWT_SECRET="$EXISTING_SECRET"
  else
    JWT_SECRET="$(tr -dc 'a-f0-9' </dev/urandom | head -c 64 || true)"
  fi
fi

# Write the config Donetick expects when DT_ENV=selfhosted
mkdir -p "$CONF_DIR"
cat > "$CONF_FILE" <<EOF
name: "Donetick @ Home"
jwt:
  secret: "${JWT_SECRET}"
database:
  type: sqlite
server:
  port: 2021
  serve_frontend: ${SERVE_FRONTEND}
realtime:
  enabled: ${REALTIME_ENABLED}
  maxConnections: ${REALTIME_MAX_CONN}
  max_connections: ${REALTIME_MAX_CONN}
EOF

# --- export env that Donetick reads (belt & suspenders) ---
export DT_ENV="selfhosted"
export DT_SQLITE_PATH="${SQLITE_PATH}"

# Force realtime via env (try both spellings just in case)
export DT_REALTIME_ENABLED="${REALTIME_ENABLED}"
export DT_REALTIME_MAXCONNECTIONS="${REALTIME_MAX_CONN}"
export DT_REALTIME_MAX_CONNECTIONS="${REALTIME_MAX_CONN}"

# Debug print (shows in add-on logs)
echo "Env overrides:"
echo "  DT_REALTIME_ENABLED=${DT_REALTIME_ENABLED}"
echo "  DT_REALTIME_MAXCONNECTIONS=${DT_REALTIME_MAXCONNECTIONS}"
echo "  DT_REALTIME_MAX_CONNECTIONS=${DT_REALTIME_MAX_CONNECTIONS}"

echo "Donetick config ready at ${CONF_FILE}. Starting..."
exec /donetick

