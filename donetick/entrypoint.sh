#!/bin/sh
set -e

OPTS="/data/options.json"
CONF_DIR="/config"
CONF_FILE="${CONF_DIR}/selfhosted.yaml"

# Read options from HA (written by Supervisor from the add-on UI)
SQLITE_PATH="$(jq -r '.sqlite_path' "$OPTS")"
JWT_SECRET_OPT="$(jq -r '.jwt_secret // empty' "$OPTS")"
SERVE_FRONTEND="$(jq -r '.serve_frontend' "$OPTS")"

# If config exists, try to reuse existing secret when user left jwt_secret blank
EXISTING_SECRET=""
if [ -f "$CONF_FILE" ]; then
  EXISTING_SECRET="$(sed -n 's/^[[:space:]]*secret:[[:space:]]*\"\?\([^\"\r\n]\+\)\"\?/\1/p' "$CONF_FILE" | head -n1)"
fi

# Decide the secret: UI value > existing > generate
JWT_SECRET="$JWT_SECRET_OPT"
if [ -z "$JWT_SECRET" ] || [ ${#JWT_SECRET} -lt 32 ]; then
  if [ -n "$EXISTING_SECRET" ] && [ ${#EXISTING_SECRET} -ge 32 ]; then
    JWT_SECRET="$EXISTING_SECRET"
  else
    JWT_SECRET="$(tr -dc 'a-f0-9' </dev/urandom | head -c 64 || true)"
  fi
fi

# Ensure /config exists and write (or rewrite) the YAML
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
EOF

# Env expected by Donetick (overrides YAML when relevant)
export DT_ENV="selfhosted"
export DT_SQLITE_PATH="${SQLITE_PATH}"

echo "Donetick config ready at ${CONF_FILE}. Starting..."
exec "$@"
