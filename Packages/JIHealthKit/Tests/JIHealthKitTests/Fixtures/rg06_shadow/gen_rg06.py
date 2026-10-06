"""RG-06 / B-112: hub-side expected verdicts for 3 shadow fixtures (10-03, 10-04, 10-05) from a
throwaway pg_dump DB. Runs the hub's own morning_go pipeline pieces (fetch_overnight_apple,
attach_recovery, plan week, evaluate) with an empty db dict (the engine's MorningGateDb())."""
import datetime as dt, json, os, sys
sys.path.insert(0, "/Volumes/data/HealthTraining"); sys.path.insert(0, "/Volumes/data/HealthTraining/scripts")
os.environ["DATABASE_URL"] = "postgresql:///ht_fixp2_l10"
import psycopg
from psycopg.rows import dict_row
import morning_go as mg
from app.vitals.recovery_inputs import load_recovery_inputs
from app.vitals.recovery_score import recovery_score
from app.planning.targets import MorningTargets

out = []
with psycopg.connect("postgresql:///ht_fixp2_l10", row_factory=dict_row) as conn:
    plan = mg.load_plan_weekdays(conn)
    for day in ["2026-10-03", "2026-10-04", "2026-10-05"]:
        today = dt.date.fromisoformat(day)
        m = mg.fetch_overnight_apple(conn, today)
        m = mg.attach_recovery(m, recovery_score(load_recovery_inputs(conn, today), today))
        verdict, conditions, _ = mg.evaluate(today, m, {"plan_weekdays": plan, "_db_ok": True}, {},
                                             targets=MorningTargets(steps_daily=15000))
        lo = today - dt.timedelta(days=120)
        nights = []
        for dso, src, col in [(4, "apple", "hrv_rmssd_ms"), (2, "garmin", "hrv_nightly_avg")]:
            for r in conn.execute(f"SELECT v.date, v.{col} AS hrv, v.rhr_bpm, s.duration_sec, COALESCE(s.sleep_score, s.sleep_score_computed) AS score "
                                  "FROM core.daily_vitals v LEFT JOIN core.daily_sleep s ON s.date=v.date AND s.dso_key=v.dso_key "
                                  "WHERE v.dso_key=%s AND v.date BETWEEN %s AND %s ORDER BY v.date", (dso, lo, today)):
                if r["hrv"] is None and r["duration_sec"] is None: continue
                nights.append({"source": src, "date": r["date"].isoformat(), "hrvRmssdMs": float(r["hrv"]) if r["hrv"] is not None else None,
                               "rhrBpm": float(r["rhr_bpm"]) if r["rhr_bpm"] is not None else None,
                               "sleepDurationSec": float(r["duration_sec"]) if r["duration_sec"] else None,
                               "sleepScore": r["score"]})
        hub = conn.execute("SELECT verdict, reason FROM plan.morning_verdict WHERE date=%s", (today,)).fetchone()
        out.append({"day": day, "nights": nights, "expectedVerdict": verdict,
                    "expectedReason": conditions[0] if conditions else verdict,
                    "storedHubVerdict": hub["verdict"] if hub else None, "storedHubReason": hub["reason"] if hub else None,
                    "recovery": m.get("recovery_score")})
    week = [{"name": plan[i][0], "type": plan[i][1]} for i in range(7)] if plan else None
json.dump({"planWeek": week, "cases": out}, open(sys.argv[1], "w"), indent=1, default=str)
for c in out: print(c["day"], "|", c["expectedVerdict"], "|", c["expectedReason"][:110], "| stored:", c["storedHubVerdict"], "|", (c["storedHubReason"] or "")[:80], "| rec", c["recovery"])
print(week)
