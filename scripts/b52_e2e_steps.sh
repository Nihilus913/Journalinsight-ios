# B-52 integration E2E (sourced by offline_sim.sh run). Phase markers advance it; every wait bounded.
# Usage: SIMU=<sim udid> OFFLINE_HUB_PORT=8734 HT=<HealthTraining checkout> bash scripts/offline_sim.sh run scripts/b52_e2e_steps.sh
#   phase 1 marker: tap the break toggle (More > Settings) offline, check the "Offline · 1 pending" marker; phase 2: after the drain.
M=/Volumes/data/JIWave/wave3-2610/b52-phase
EV=/Volumes/data/JIWave/wave3-2610/b52-evidence
SIMU=${SIMU:?}
waitfor() { for _ in $(seq 1 180); do [ -f "$M.$1" ] && return 0; sleep 5; done; echo "TIMEOUT waiting $1"; return 1; }
TABS="today recovery training more"
TMPS=${TMPDIR:-/tmp}/b52shots; mkdir -p "$TMPS"
shot() { perl -e 'alarm shift; exec @ARGV' 60 xcrun simctl io "$SIMU" screenshot "$TMPS/$1.png" >/dev/null 2>&1 && mv "$TMPS/$1.png" "$EV/$1.png" && echo "shot $1" || echo "shot FAILED $1"; }
L() { perl -e 'alarm shift; exec @ARGV' "$@"; }
go() {
  L 150 xcrun simctl terminate "$SIMU" "$BUNDLE" >/dev/null 2>&1 || true
  L 180 xcrun simctl launch "$SIMU" "$BUNDLE" -hub-url "http://127.0.0.1:$PORT" -hub-token "$TOKEN" -no-push -no-healthkit -no-onboarding "$@" >/dev/null 2>&1 \
    && echo "launched $*" || echo "launch FAILED $*"
}
walk() { # $1 = prefix
  for t in $TABS; do go -start-tab "$t"; sleep 12; shot "$1-$t"; done
  for r in kpiList dataQuality; do go -push-route "$r"; sleep 12; shot "$1-$r"; done
}
assert_hub_up
psql -d "$DB" -c "SELECT 'before', count(*) FILTER (WHERE end_date IS NULL), coalesce(max(break_id),0) FROM plan.training_break"
walk online
hub_stop; assert_hub_down
walk offline
go -start-tab more; sleep 6
echo "PHASE down-ready"; waitfor 1
hub_start; assert_hub_up
echo "PHASE back-up"; waitfor 2
psql -d "$DB" -c "SELECT 'after', break_id, start_date, end_date, created_at FROM plan.training_break ORDER BY break_id DESC LIMIT 3"
grep -E "training-break|push-garmin|weigh" "$STATE/hub.log" | grep -E 'PUT|POST' | tail -20
echo "PHASE done"; waitfor 3
