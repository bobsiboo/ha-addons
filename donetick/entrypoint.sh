#!/bin/sh
set -e

OPTS="/data/options.json"
CONF_DIR="/config"
CONF_FILE="${CONF_DIR}/selfhosted.yaml"

# ---------- READ BASIC OPTIONS ----------
SQLITE_PATH="$(jq -r '.sqlite_path' "$OPTS")"
JWT_SECRET_OPT="$(jq -r '.jwt_secret // empty' "$OPTS")"
SERVE_FRONTEND="$(jq -r '.serve_frontend' "$OPTS")"
REALTIME_ENABLED="$(jq -r '.realtime_enabled' "$OPTS")"

# ---------- READ ADVANCED TOGGLE ----------
ADVANCED="$(jq -r '.advanced' "$OPTS")"

# ---------- READ ADVANCED (might be ignored if ADVANCED=false) ----------
RT_MAX_CONN="$(jq -r '.realtime_max_connections' "$OPTS")"
RT_MAX_CONN_PER_USER="$(jq -r '.realtime_max_connections_per_user' "$OPTS")"
RT_EVENT_QUEUE_SIZE="$(jq -r '.realtime_event_queue_size' "$OPTS")"
RT_HEARTBEAT_INTERVAL="$(jq -r '.realtime_heartbeat_interval' "$OPTS")"
RT_CONNECTION_TIMEOUT="$(jq -r '.realtime_connection_timeout' "$OPTS")"
RT_CLEANUP_INTERVAL="$(jq -r '.realtime_cleanup_interval' "$OPTS")"
RT_STALE_THRESHOLD="$(jq -r '.realtime_stale_threshold' "$OPTS")"
RT_SSE_ENABLED="$(jq -r '.realtime_sse_enabled' "$OPTS")"
RT_ENABLE_COMPRESSION="$(jq -r '.realtime_enable_compression' "$OPTS")"
RT_ENABLE_STATS="$(jq -r '.realtime_enable_stats' "$OPTS")"
# list to CSV for env; YAML will get real list below
RT_ALLOWED_ORIGINS_CSV="$(jq -r '.realtime_allowed_origins | join(",")' "$OPTS")"

# ---------- SANITIZE / DEFAULTS ----------
# booleans
[ "$SERVE_FRONTEND" != "true" ] && [ "$SERVE_FRONTEND" != "false" ] && SERVE_FRONTEND=true
[ "$REALTIME_ENABLED" != "true" ] && [ "$REALTIME_ENABLED" != "false" ] && REALTIME_ENABLED=true
[ "$ADVANCED" != "true" ] && [ "$ADVANCED" != "false" ] && ADVANCED=false

# If ADVANCED=false, use safe upstream defaults (matches sample selfhosted.yaml)
if [ "$ADVANCED" = "false" ]; then
  RT_MAX_CONN=1000
  RT_MAX_CONN_PER_USER=5
  RT_EVENT_QUEUE_SIZE=2048
  RT_HEARTBEAT_INTERVAL="60s"
  RT_CONNECTION_TIMEOUT="120s"
  RT_CLEANUP_INTERVAL="2m"
  RT_STALE_THRESHOLD="5m"
  RT_SSE_ENABLED="true"
  RT_ENABLE_COMPRESSION="true"
  RT_ENABLE_STATS="true"
  RT_ALLOWED_ORIGINS_CSV="*"
else
  # enforce sane minimums if user set bad/zero values
  [ -z "$RT_MAX_CONN" ] || [ "$RT_MAX_CONN" -le 0 ] && RT_MAX_CONN=1000
  [ -z "$RT_MAX_CONN_PER_USER" ] || [ "$RT_MAX_CONN_PER_USER" -le 0 ] && RT_MAX_CONN_PER_USER=5
  [ -z "$RT_EVENT_QUEUE_SIZE" ] || [ "$RT_EVENT_QUEUE_SIZE" -le 0 ] && RT_EVENT_QUEUE_SIZE=2048
  [ -z "$RT_HEARTBEAT_INTERVAL" ] && RT_HEARTBEAT_INTERVAL="60s"
  [ -z "$RT_CONNECTION_TIMEOUT" ] && RT_CONNECTION_TIMEOUT="120s"
  [ -z "$RT_CLEANUP_INTERVAL" ] && RT_CLEANUP_INTERVAL="2m"
  [ -z "$RT_STALE_THRESHOLD" ] && RT_STALE_THRESHOLD="5m"
  [ "$RT_SSE_ENABLED" != "true" ] && [ "$RT_SSE_ENABLED" != "false" ] && RT_SSE_ENABLED="true"
  [ "$RT_ENABLE_COMPRESSION" != "true" ] && [ "$RT_ENABLE_COMPRESSION" != "false" ] && RT_ENABLE_COMPRESSION="true"
  [ "$RT_ENABLE_STATS" != "true" ] && [ "$RT_ENABLE_STATS" != "false" ] && RT_ENABLE_STATS="true"
  [ -z "$RT_ALLOWED_ORIGINS_CSV" ] && RT_ALLOWED_ORIGINS_CSV="*"
fi

# ---------- JWT SECRET (reuse or generate) ----------
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

# ---------- WRITE YAML (snake_case + camelCase for safety) ----------
mkdir -p "$CONF_DIR"
# Build YAML list of allowed origins
ALLOWED_LIST_YAML=""
IFS=','; for o in $RT_ALLOWED_ORIGINS_CSV; do
  [ -n "$o" ] && ALLOWED_LIST_YAML="${ALLOWED_LIST_YAML}    - \"${o}\"\n"
done
unset IFS
[ -z "$ALLOWED_LIST_YAML" ] && ALLOWED_LIST_YAML="    - \"*\"\n"

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
  sse_enabled: ${RT_SSE_ENABLED}
  heartbeat_interval: ${RT_HEARTBEAT_INTERVAL}
  connection_timeout: ${RT_CONNECTION_TIMEOUT}
  max_connections: ${RT_MAX_CONN}
  max_connections_per_user: ${RT_MAX_CONN_PER_USER}
  event_queue_size: ${RT_EVENT_QUEUE_SIZE}
  cleanup_interval: ${RT_CLEANUP_INTERVAL}
  stale_threshold: ${RT_STALE_THRESHOLD}
  enable_compression: ${RT_ENABLE_COMPRESSION}
  enable_stats: ${RT_ENABLE_STATS}
  allowed_origins:
$(printf "%b" "$ALLOWED_LIST_YAML")  heartbeatInterval: ${RT_HEARTBEAT_INTERVAL}
  connectionTimeout: ${RT_CONNECTION_TIMEOUT}
  maxConnections: ${RT_MAX_CONN}
  maxConnectionsPerUser: ${RT_MAX_CONN_PER_USER}
  eventQueueSize: ${RT_EVENT_QUEUE_SIZE}
  cleanupInterval: ${RT_CLEANUP_INTERVAL}
  staleThreshold: ${RT_STALE_THRESHOLD}
  enableCompression: ${RT_ENABLE_COMPRESSION}
  enableStats: ${RT_ENABLE_STATS}
EOF

# ---------- ENV OVERRIDES (so nothing falls back to 0) ----------
export DT_ENV="selfhosted"
export DT_SQLITE_PATH="${SQLITE_PATH}"

export DT_REALTIME_ENABLED="${REALTIME_ENABLED}"
export DT_REALTIME_SSE_ENABLED="${RT_SSE_ENABLED}"
export DT_REALTIME_HEARTBEAT_INTERVAL="${RT_HEARTBEAT_INTERVAL}"
export DT_REALTIME_CONNECTION_TIMEOUT="${RT_CONNECTION_TIMEOUT}"
export DT_REALTIME_MAX_CONNECTIONS="${RT_MAX_CONN}"
export DT_REALTIME_MAX_CONNECTIONS_PER_USER="${RT_MAX_CONN_PER_USER}"
export DT_REALTIME_EVENT_QUEUE_SIZE="${RT_EVENT_QUEUE_SIZE}"
export DT_REALTIME_CLEANUP_INTERVAL="${RT_CLEANUP_INTERVAL}"
export DT_REALTIME_STALE_THRESHOLD="${RT_STALE_THRESHOLD}"
export DT_REALTIME_ENABLE_COMPRESSION="${RT_ENABLE_COMPRESSION}"
export DT_REALTIME_ENABLE_STATS="${RT_ENABLE_STATS}"
export DT_REALTIME_ALLOWED_ORIGINS="${RT_ALLOWED_ORIGINS_CSV}"

echo "Env overrides:"
echo "  DT_REALTIME_ENABLED=${DT_REALTIME_ENABLED}"
echo "  DT_REALTIME_MAX_CONNECTIONS=${DT_REALTIME_MAX_CONNECTIONS}"
echo "  DT_REALTIME_MAX_CONNECTIONS_PER_USER=${DT_REALTIME_MAX_CONNECTIONS_PER_USER}"
echo "  DT_REALTIME_EVENT_QUEUE_SIZE=${DT_REALTIME_EVENT_QUEUE_SIZE}"
echo "  DT_REALTIME_CLEANUP_INTERVAL=${DT_REALTIME_CLEANUP_INTERVAL}"
echo "  DT_REALTIME_STALE_THRESHOLD=${DT_REALTIME_STALE_THRESHOLD}"

echo "Donetick config ready at ${CONF_FILE}. Starting..."
exec /donetick
