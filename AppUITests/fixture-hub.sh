#!/usr/bin/env bash
# fixture-hub.sh — W-UITEST UT-1: the throwaway HealthTraining hub the AppUITests target talks to.
#
#   bash AppUITests/fixture-hub.sh test   # clone + seed + hub → xcodebuild test -scheme AppUITests → down
#   bash AppUITests/fixture-hub.sh up     # clone the DB, start the hub, seed; stays in the foreground
#                                         # until the hub exits (run it in its own terminal)
#   bash AppUITests/fixture-hub.sh down   # stop the hub, drop the throwaway DB
#
# The source DB is only READ (pg_dump). Every write the UI tests make (a day change, a deleted
# workout, a targets PUT) lands in the throwaway DB `$UITEST_DB`, recreated on every start — so a
# run is repeatable and the prod DB, the prod hub (:8000) and Garmin are never written.
# The hub stays a CHILD of this script (never nohup'ed / detached): Postgres.app verifies "trust"
# clients through their parent app and refuses an orphaned process (a permission dialog).
# Seeded fixtures (the throwaway DB only):
#   - G-3: today's gate answered automatically ("GATED" from "Easy Run", source 'auto').
#   - FIX9-1: the latest Apple workout with zone_time moved to today, Watch bounds fixed to
#     <117 / 117–139 / 139–160 / 160–176 / 176+ (5 / 10 / 15 / 2 / 1 min).
#   - UT-2: a segments-only workout template "UITest Segments Tempo" (compat steps: [], 2 segments).
# Env: HT (HealthTraining checkout, default ~/Documents/HealthTraining) · PY (its venv python)
#      PGBIN · UITEST_SRC_DB (default health_training) · UITEST_DB (default ht_uitest)
#      UITEST_HUB_PORT (default 8150) · UITEST_HUB_TOKEN (default uitest-fixture-token)
#      UITEST_STATE (pid + hub log dir) · UITEST_SHOTS (proof PNG dir) · DEST · DERIVED
# Extra arguments after `test` go to xcodebuild (e.g. -only-testing:AppUITests/TrainingProofTests).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PGBIN=${PGBIN:-/Applications/Postgres.app/Contents/Versions/latest/bin}
HT=${HT:-$HOME/Documents/HealthTraining}
PY=${PY:-$HT/.venv311/bin/python}
SRC_DB=${UITEST_SRC_DB:-health_training}
DB=${UITEST_DB:-ht_uitest}
PORT=${UITEST_HUB_PORT:-8150}
TOKEN=${UITEST_HUB_TOKEN:-uitest-fixture-token}
STATE=${UITEST_STATE:-${TMPDIR:-/tmp}/ji-uitest-hub}
DEST=${DEST:-platform=iOS Simulator,name=iPhone 18 Pro}

[ "$DB" != "$SRC_DB" ] || { echo "fixture-hub: refusing — UITEST_DB equals the source DB" >&2; exit 2; }
case "$DB" in health_training|health_training_test) echo "fixture-hub: refusing to touch $DB" >&2; exit 2 ;; esac
[ "$PORT" != 8000 ] || { echo "fixture-hub: refusing — :8000 is the prod hub" >&2; exit 2; }

psql() { "$PGBIN/psql" -X -v ON_ERROR_STOP=1 -q -At "$@"; }

seed() {
  psql -d "$DB" <<'SQL'
DELETE FROM plan.decision_log WHERE date = current_date;
INSERT INTO plan.decision_log (date, window_days, recommendation, user_choice, source,
                               auto_classification, auto_activity, logged_at)
VALUES (current_date, 7, 'GO', 'y', 'auto', 'GATED', 'Easy Run', now());
INSERT INTO core.day (date) VALUES (current_date) ON CONFLICT DO NOTHING;
CREATE TEMP TABLE z AS
  SELECT aw.activity_id FROM import.apple_workout aw JOIN core.activity a USING (activity_id)
  WHERE aw.zone_time IS NOT NULL ORDER BY a.start_time_utc DESC LIMIT 1;
UPDATE core.activity SET date = current_date, start_time_utc = now() - interval '2 hours'
  WHERE activity_id IN (SELECT activity_id FROM z);
UPDATE import.apple_workout SET date = current_date, zone_time = '[
  {"zone": 1, "seconds": 300, "lower_bpm": null, "upper_bpm": 117},
  {"zone": 2, "seconds": 600, "lower_bpm": 117, "upper_bpm": 139},
  {"zone": 3, "seconds": 900, "lower_bpm": 139, "upper_bpm": 160},
  {"zone": 4, "seconds": 120, "lower_bpm": 160, "upper_bpm": 176},
  {"zone": 5, "seconds": 60, "lower_bpm": 176, "upper_bpm": null}]'::jsonb
  WHERE activity_id IN (SELECT activity_id FROM z);
SQL
  [ "$(psql -d "$DB" -c "SELECT count(*) FROM import.apple_workout WHERE date = current_date AND zone_time IS NOT NULL")" -ge 1 ] \
    || { echo "fixture-hub: no Apple workout with zones to seed" >&2; exit 2; }
  # The segments-only template goes through the hub itself (its validation, its stored shape).
  curl -fsS -o /dev/null -X POST "http://127.0.0.1:$PORT/api/v1/planning/workout-templates" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    --data @"$HERE/Fixtures/segments-only-template.json"
}

start() {
  down >/dev/null 2>&1 || true
  mkdir -p "$STATE"
  "$PGBIN/createdb" "$DB"
  "$PGBIN/pg_dump" -Fc "$SRC_DB" | "$PGBIN/pg_restore" --no-owner -d "$DB"
  (cd "$HT" && exec env DATABASE_URL="dbname=$DB" HT_API_TOKEN="$TOKEN" \
    "$PY" -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT") >"$STATE/hub.log" 2>&1 &
  echo $! >"$STATE/hub.pid"
  for _ in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" || true)" = 200 ] && break
    sleep 1
  done
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" || true)" = 200 ] \
    || { echo "fixture-hub: hub on :$PORT never answered /health (see $STATE/hub.log)" >&2; exit 2; }
  seed
  echo "fixture-hub: up — http://127.0.0.1:$PORT (db $DB, log $STATE/hub.log)"
}

down() {
  if [ -f "$STATE/hub.pid" ]; then kill "$(cat "$STATE/hub.pid")" 2>/dev/null || true; rm -f "$STATE/hub.pid"; fi
  "$PGBIN/dropdb" --if-exists "$DB"
}

up() { start; wait "$(cat "$STATE/hub.pid")"; }

run_tests() {
  start
  trap down EXIT
  DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} \
  TEST_RUNNER_UITEST_HUB_URL="http://127.0.0.1:$PORT" TEST_RUNNER_UITEST_HUB_TOKEN="$TOKEN" \
  TEST_RUNNER_UITEST_SHOTS="${UITEST_SHOTS:-}" TEST_RUNNER_UITEST_HUB_LOG="$STATE/hub.log" \
    xcodebuild -project "$ROOT/JournalInsight.xcodeproj" -scheme AppUITests -destination "$DEST" \
      ${DERIVED:+-derivedDataPath "$DERIVED"} test "$@"
}

cmd=${1:-}; shift || true
case "$cmd" in
  up) up ;;
  down) down ;;
  test) run_tests "$@" ;;
  *) sed -n 2,24p "$0"; exit 2 ;;
esac
