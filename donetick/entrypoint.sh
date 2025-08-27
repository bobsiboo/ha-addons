#!/bin/sh
set -e

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

OPTS="/data/options.json"
CONF_DIR="/config"
CONF_FILE="${CONF_DIR}/selfhosted.yaml"

log "==== Donetick add-on start ===="

# ---------- READ BASIC OPTIONS ----------
SQLITE_PATH="$(jq -r '.sqlite_path // "/data/donetick.db"' "$OPTS")"
JWT_SECRET_OPT="$(jq -r '.jwt_secret // empty' "$OPTS")"
SERVE_FRONTEND="$(jq -r '.serve_frontend // true' "$OPTS")"
REALTIME_ENABLED="$(jq -r '.realtime_enabled // true' "$OPTS")"

# ---------- READ ADVANCED TOGGLE ----------
ADVANCED="$(jq -r '.advanced // false' "$OPTS")"

# ---------- READ ADVANCED (used when ADVANCED=true; defaults applied below) ----------
RT_MAX_CONN="$(jq -r '.realtime_max_connections // empty' "$OPTS")"
RT_MAX_CONN_PER_USER="$(jq -r '.realtime_max_connections_per_user // empty' "$OPTS")"
RT_EVENT_QUEUE_SIZE="$(jq -r '.realtime_event_queue_size // empty' "$OPTS")"
RT_HEARTBEAT_INTERVAL="$(jq -r '.realtime_heartbeat_interval // empty' "$OPTS")"
RT_CONNECTION_TIMEOUT="$(jq -r '.realtime_connection_timeout // empty' "$OPTS")"
RT_CLEANUP_INTERVAL="$(jq -r '.realtime_cleanup_interval // empty' "$OPTS")"
RT_STALE_THRESHOLD="$(jq -r '.realtime_stale_threshold // empty' "$OPTS")"
RT_SSE_ENABLED="$(jq -r '.realtime_sse_enabled // true' "$OPTS")"
RT_ENABLE_COMPRESSION="$(jq -r '.realtime_enable_compression // true' "$OPTS")"
RT_ENABLE_STATS="$(jq -r '.realtime_enable_stats // true' "$OPTS")"
SERVER_CORS_CSV="$(jq -r '.server_cors_allow_origins // ["*"] | join(",")' "$OPTS")"
[ -z "$SERVER_CORS_CSV" ] && SERVER_CORS_CSV="*"

SERVER_RATE_LIMIT="$(jq -r '.server_rate_limit // 300' "$OPTS")"
SERVER_RATE_PERIOD="$(jq -r '.server_rate_period // "60s"' "$OPTS")"
SERVER_READ_TIMEOUT="$(jq -r '.server_read_timeout // "10s"' "$OPTS")"
SERVER_WRITE_TIMEOUT="$(jq -r '.server_write_timeout // "10s"' "$OPTS")"
case "$SERVER_RATE_LIMIT" in ''|*[!0-9]*) SERVER_RATE_LIMIT=300;; esac


# ---------- LIST OPTIONS (CSV for printing/env) ----------
RT_ALLOWED_ORIGINS_CSV="$(jq -r '.realtime_allowed_origins // ["*"] | join(",")' "$OPTS")"
SERVER_CORS_CSV="$(jq -r '.server_cors_allow_origins // ["*"] | join(",")' "$OPTS")"
[ -z "$RT_ALLOWED_ORIGINS_CSV" ] && RT_ALLOWED_ORIGINS_CSV="*"
[ -z "$SERVER_CORS_CSV" ] && SERVER_CORS_CSV="*"

# ---------- DEBUG TOGGLES ----------
DEBUG_LOGGING="$(jq -r '.debug_logging // false' "$OPTS")"
LOG_LEVEL="$(jq -r '.logging_level // "info"' "$OPTS")"
LOG_ENCODING="$(jq -r '.logging_encoding // "console"' "$OPTS")"
LOG_DEVELOPMENT="$(jq -r '.logging_development // false' "$OPTS")"

# Compute effective logging config
if [ "$DEBUG_LOGGING" = "true" ]; then
  LOG_LEVEL="debug"
  LOG_ENCODING="console"
  LOG_DEVELOPMENT="true"
  GIN_MODE="debug"
else
  case "$LOG_LEVEL" in debug|info|warn|error) ;; *) LOG_LEVEL="info";; esac
  case "$LOG_ENCODING" in console|json) ;; *) LOG_ENCODING="console";; esac
  case "$LOG_DEVELOPMENT" in true|false) ;; *) LOG_DEVELOPMENT="false";; esac
  GIN_MODE="release"
fi

# ---------- SANITIZE / DEFAULTS ----------
case "$SERVE_FRONTEND" in true|false) ;; *) SERVE_FRONTEND=true;; esac
case "$REALTIME_ENABLED" in true|false) ;; *) REALTIME_ENABLED=true;; esac
case "$ADVANCED" in true|false) ;; *) ADVANCED=false;; esac
case "$RT_SSE_ENABLED" in true|false) ;; *) RT_SSE_ENABLED=true;; esac
case "$RT_ENABLE_COMPRESSION" in true|false) ;; *) RT_ENABLE_COMPRESSION=true;; esac
case "$RT_ENABLE_STATS" in true|false) ;; *) RT_ENABLE_STATS=true;; esac

if [ "$ADVANCED" = "false" ]; then
  # Upstream-style safe defaults
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
  # Enforce sane minimums if user supplied zeros/empties
  [ -n "$RT_MAX_CONN" ] && [ "$RT_MAX_CONN" -gt 0 ] || RT_MAX_CONN=1000
  [ -n "$RT_MAX_CONN_PER_USER" ] && [ "$RT_MAX_CONN_PER_USER" -gt 0 ] || RT_MAX_CONN_PER_USER=5
  [ -n "$RT_EVENT_QUEUE_SIZE" ] && [ "$RT_EVENT_QUEUE_SIZE" -gt 0 ] || RT_EVENT_QUEUE_SIZE=2048
  [ -n "$RT_HEARTBEAT_INTERVAL" ] || RT_HEARTBEAT_INTERVAL="60s"
  [ -n "$RT_CONNECTION_TIMEOUT" ] || RT_CONNECTION_TIMEOUT="120s"
  [ -n "$RT_CLEANUP_INTERVAL" ] || RT_CLEANUP_INTERVAL="2m"
  [ -n "$RT_STALE_THRESHOLD" ] || RT_STALE_THRESHOLD="5m"
  [ -z "$RT_ALLOWED_ORIGINS_CSV" ] && RT_ALLOWED_ORIGINS_CSV="*"
fi

# ---------- JWT SECRET (reuse or generate) ----------
EXISTING_SECRET=""
if [ -f "$CONF_FILE" ]; then
  EXISTING_SECRET="$(sed -n 's/^[[:space:]]*secret:[[:space:]]*"\{0,1\}\([^"]\{32,\}\)".*$/\1/p' "$CONF_FILE" | head -n1)"
fi
JWT_SECRET="$JWT_SECRET_OPT"
if [ -z "$JWT_SECRET" ] || [ ${#JWT_SECRET} -lt 32 ]; then
  if [ -n "$EXISTING_SECRET" ] && [ ${#EXISTING_SECRET} -ge 32 ]; then
    JWT_SECRET="$EXISTING_SECRET"
  else
    JWT_SECRET="$(tr -dc 'a-f0-9' </dev/urandom | head -c 64 || true)"
  fi
fi

# ---------- WRITE YAML (snake_case only; safe indentation) ----------
mkdir -p "$CONF_DIR"
{
  echo 'name: "Donetick @ Home"'
  echo 'is_done_tick_dot_com: false'
  echo 'is_user_creation_disabled: false'

  echo 'jwt:'
  echo "  secret: \"${JWT_SECRET}\""

  echo 'database:'
  echo '  type: sqlite'
  echo '  migration: true'

  echo 'server:'
  echo '  port: 2021'
  echo "  serve_frontend: ${SERVE_FRONTEND}"
  echo "  read_timeout: ${SERVER_READ_TIMEOUT}"
  echo "  write_timeout: ${SERVER_WRITE_TIMEOUT}"
  echo "  rate_period: ${SERVER_RATE_PERIOD}"
  echo "  rate_limit: ${SERVER_RATE_LIMIT}"
  echo '  cors_allow_origins:'
  set -f
  _CORS_CSV="${SERVER_CORS_CSV:-*}"
  IFS=','; for o in $_CORS_CSV; do
    [ -n "$o" ] && printf '    - "%s"\n' "$o"
  done
  set +f
  unset IFS


  echo 'logging:'
  echo "  level: \"${LOG_LEVEL}\""
  echo "  encoding: \"${LOG_ENCODING}\""
  echo "  development: ${LOG_DEVELOPMENT}"

  echo 'realtime:'
  echo "  enabled: ${REALTIME_ENABLED}"
  echo "  sse_enabled: ${RT_SSE_ENABLED}"
  echo "  heartbeat_interval: ${RT_HEARTBEAT_INTERVAL}"
  echo "  connection_timeout: ${RT_CONNECTION_TIMEOUT}"
  echo "  max_connections: ${RT_MAX_CONN}"
  echo "  max_connections_per_user: ${RT_MAX_CONN_PER_USER}"
  echo "  event_queue_size: ${RT_EVENT_QUEUE_SIZE}"
  echo "  cleanup_interval: ${RT_CLEANUP_INTERVAL}"
  echo "  stale_threshold: ${RT_STALE_THRESHOLD}"
  echo "  enable_compression: ${RT_ENABLE_COMPRESSION}"
  echo "  enable_stats: ${RT_ENABLE_STATS}"
  echo "  allowed_origins:"
  set -f
  _RT_CSV="${RT_ALLOWED_ORIGINS_CSV:-*}"
  IFS=','; for o in $_RT_CSV; do
    [ -n "$o" ] && printf '    - "%s"\n' "$o"
  done
  set +f
  unset IFS
} > "$CONF_FILE"

# ---------- SHOW THE FILE WITH LINE NUMBERS ----------
log "--- Rendered /config/selfhosted.yaml (first 120 lines) ---"
nl -ba "$CONF_FILE" | sed -n '1,120p'

# ---------- ENV OVERRIDES ----------
export DT_ENV="selfhosted"

# DB
export DT_DATABASE_TYPE="sqlite"
export DT_SQLITE_PATH="${SQLITE_PATH}"
export DT_DATABASE_SQLITE_PATH="${SQLITE_PATH}"
export DT_DATABASE_MIGRATION="true"

# Signup flags
export DT_IS_USER_CREATION_DISABLED="false"
export DONETICK_DISABLE_SIGNUP="false"
export DT_IS_DONE_TICK_DOT_COM="false"
export DT_NAME="selfhosted"

# CORS
export DT_SERVER_CORS_ALLOW_ORIGINS="${SERVER_CORS_CSV}"

# Realtime
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
export DT_SERVER_READ_TIMEOUT="${SERVER_READ_TIMEOUT}"
export DT_SERVER_WRITE_TIMEOUT="${SERVER_WRITE_TIMEOUT}"
export DT_SERVER_RATE_PERIOD="${SERVER_RATE_PERIOD}"
export DT_SERVER_RATE_LIMIT="${SERVER_RATE_LIMIT}"
export DT_SERVER_CORS_ALLOW_ORIGINS="${SERVER_CORS_CSV}"


# Logging
export DT_LOGGING_LEVEL="${LOG_LEVEL}"
export DT_LOGGING_ENCODING="${LOG_ENCODING}"
export DT_LOGGING_DEVELOPMENT="${LOG_DEVELOPMENT}"
export GIN_MODE="${GIN_MODE}"

# ---------- LOG A QUICK SUMMARY ----------
log "Env overrides:"
log "  DT_REALTIME_ENABLED=${DT_REALTIME_ENABLED}"
log "  DT_REALTIME_MAX_CONNECTIONS=${DT_REALTIME_MAX_CONNECTIONS}"
log "  DT_REALTIME_MAX_CONNECTIONS_PER_USER=${DT_REALTIME_MAX_CONNECTIONS_PER_USER}"
log "  DT_REALTIME_EVENT_QUEUE_SIZE=${DT_REALTIME_EVENT_QUEUE_SIZE}"
log "  DT_REALTIME_CLEANUP_INTERVAL=${DT_REALTIME_CLEANUP_INTERVAL}"
log "  DT_REALTIME_STALE_THRESHOLD=${DT_REALTIME_STALE_THRESHOLD}"
log "DB env:"
log "  DT_DATABASE_TYPE=${DT_DATABASE_TYPE}"
log "  DT_DATABASE_SQLITE_PATH=${DT_DATABASE_SQLITE_PATH}"
log "  DT_DATABASE_MIGRATION=${DT_DATABASE_MIGRATION}"
log "Signup/CORS env:"
log "  DT_IS_USER_CREATION_DISABLED=${DT_IS_USER_CREATION_DISABLED}"
log "  DONETICK_DISABLE_SIGNUP=${DONETICK_DISABLE_SIGNUP}"
log "  DT_SERVER_CORS_ALLOW_ORIGINS=${DT_SERVER_CORS_ALLOW_ORIGINS}"
log "Server limits/CORS:"
log "  DT_SERVER_RATE_LIMIT=${DT_SERVER_RATE_LIMIT}"
log "  DT_SERVER_RATE_PERIOD=${DT_SERVER_RATE_PERIOD}"
log "  DT_SERVER_READ_TIMEOUT=${DT_SERVER_READ_TIMEOUT}"
log "  DT_SERVER_WRITE_TIMEOUT=${DT_SERVER_WRITE_TIMEOUT}"
log "  DT_SERVER_CORS_ALLOW_ORIGINS=${DT_SERVER_CORS_ALLOW_ORIGINS}"


log "Donetick config ready at ${CONF_FILE}. Starting..."
exec /donetick
