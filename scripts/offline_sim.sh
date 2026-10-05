#!/usr/bin/env bash
# offline_sim.sh — B-52 p1 (e): drive the hub DOWN and back UP around a simulator check, and assert
# what the hub's DB holds afterwards. Throwaway only: the prod DB is only READ (pg_dump), the hub
# runs on its own port against a cloned DB, and nothing here touches :8000 or Garmin.
#
#   bash scripts/offline_sim.sh selftest           # up → assert up → stop → assert down → start → assert up → down
#   bash scripts/offline_sim.sh run steps.sh       # up, then source steps.sh with the helpers below, then down
#   bash scripts/offline_sim.sh down               # stop the hub, drop the throwaway DB
#
# Helpers available to a `run` steps file (each bounded; none waits forever):
#   hub_stop · hub_start · assert_hub_down · assert_hub_up
#   assert_sql "<SELECT returning one value>" "<expected>"   (against the throwaway DB)
#   sim_launch <udid> [extra launch args…]  · sim_shot <udid> <png>   (app pointed at this hub)
# Env: HT (HealthTraining checkout, default ~/Documents/HealthTraining) · PY · PGBIN
#      OFFLINE_SRC_DB (default health_training) · OFFLINE_DB (default ht_b52_offline)
#      OFFLINE_HUB_PORT (default 8721) · OFFLINE_HUB_TOKEN · OFFLINE_STATE (pid + log dir)
# The hub stays a CHILD of this script (Postgres.app refuses orphaned "trust" clients).
set -euo pipefail

PGBIN=${PGBIN:-/Applications/Postgres.app/Contents/Versions/latest/bin}
HT=${HT:-$HOME/Documents/HealthTraining}
PY=${PY:-$HT/.venv311/bin/python}
SRC_DB=${OFFLINE_SRC_DB:-health_training}
DB=${OFFLINE_DB:-ht_b52_offline}
PORT=${OFFLINE_HUB_PORT:-8721}
TOKEN=${OFFLINE_HUB_TOKEN:-b52-offline-token}
STATE=${OFFLINE_STATE:-${TMPDIR:-/tmp}/ji-b52-offline}
BUNDLE=toby913.JournalInsight
export GARTH_TELEMETRY_ENABLED=false

[ "$DB" != "$SRC_DB" ] || { echo "offline_sim: refusing — OFFLINE_DB equals the source DB" >&2; exit 2; }
case "$DB" in health_training|health_training_test) echo "offline_sim: refusing to touch $DB" >&2; exit 2 ;; esac
[ "$PORT" != 8000 ] || { echo "offline_sim: refusing — :8000 is the prod hub" >&2; exit 2; }

psql() { "$PGBIN/psql" -X -v ON_ERROR_STOP=1 -q -At "$@"; }
health_code() { curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" || true; }

hub_start() {
  mkdir -p "$STATE"
  (cd "$HT" && exec env DATABASE_URL="dbname=$DB" HT_API_TOKEN="$TOKEN" GARTH_TELEMETRY_ENABLED=false \
    "$PY" -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT") >>"$STATE/hub.log" 2>&1 &
  echo $! >"$STATE/hub.pid"
  for _ in $(seq 1 60); do [ "$(health_code)" = 200 ] && return 0; sleep 1; done
  echo "offline_sim: hub on :$PORT never answered /health (see $STATE/hub.log)" >&2; return 2
}

hub_stop() {
  if [ -f "$STATE/hub.pid" ]; then
    local pid; pid=$(cat "$STATE/hub.pid")
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$STATE/hub.pid"
  fi
}

assert_hub_down() { local c; c=$(health_code); [ "$c" = 000 ] || { echo "ASSERT FAIL hub_down: /health=$c" >&2; return 1; }; echo "ok hub down"; }
assert_hub_up()   { local c; c=$(health_code); [ "$c" = 200 ] || { echo "ASSERT FAIL hub_up: /health=$c" >&2; return 1; }; echo "ok hub up"; }

assert_sql() {
  local got; got=$(psql -d "$DB" -c "$1")
  [ "$got" = "$2" ] || { echo "ASSERT FAIL sql: $1 → '$got' (want '$2')" >&2; return 1; }
  echo "ok sql: $1 = $2"
}

# The app pointed at this hub (DEBUG launch-arg connection config, see AppEnvironment.launchArgumentConfig).
sim_launch() {
  local udid=$1; shift
  perl -e 'alarm shift; exec @ARGV' 60 xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  perl -e 'alarm shift; exec @ARGV' 60 xcrun simctl launch "$udid" "$BUNDLE" \
    -hub-url "http://127.0.0.1:$PORT" -hub-token "$TOKEN" -no-push -no-healthkit "$@"
}
sim_shot() { perl -e 'alarm shift; exec @ARGV' 60 xcrun simctl io "$1" screenshot "$2" >/dev/null; echo "shot $2"; }

up() {
  down >/dev/null 2>&1 || true
  mkdir -p "$STATE"; : >"$STATE/hub.log"
  "$PGBIN/createdb" "$DB"
  "$PGBIN/pg_dump" -Fc "$SRC_DB" | "$PGBIN/pg_restore" --no-owner -d "$DB"
  hub_start
  echo "offline_sim: up — http://127.0.0.1:$PORT (db $DB, log $STATE/hub.log)"
}

down() { hub_stop; "$PGBIN/dropdb" --if-exists "$DB"; }

selftest() {
  up; trap down EXIT
  assert_hub_up
  hub_stop; assert_hub_down
  hub_start; assert_hub_up
  assert_sql "SELECT 1" "1"
  echo "offline_sim: selftest passed"
}

run_steps() {
  [ -f "${1:-}" ] || { echo "offline_sim: run needs a steps file" >&2; exit 2; }
  up; trap down EXIT
  # shellcheck disable=SC1090
  source "$1"
}

cmd=${1:-}; shift || true
case "$cmd" in
  selftest) selftest ;;
  run) run_steps "$@" ;;
  down) down ;;
  *) sed -n 2,18p "$0"; exit 2 ;;
esac
