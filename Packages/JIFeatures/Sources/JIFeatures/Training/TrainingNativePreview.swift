import SwiftUI
import JICore
import JIDesign

/// §8.5 registry entry "Training" — the same cards `TrainingView.loaded` composes, over a decoded
/// hub fixture. Test/sweep only; the app always routes to `TrainingView`.
struct TrainingNativePreview: View {
    private let today = "2026-09-21"

    private var gate: GateResponse? {
        l5Fixture(GateResponse.self, """
        {"averages": {"trends": {}, "avg_kcal_7d": 2410, "avg_protein_7d": 168, "acwr": 1.08},
         "daily": [
           {"date": "2026-09-15", "kcal_burned_active": 420},
           {"date": "2026-09-16", "kcal_burned_active": 90},
           {"date": "2026-09-17", "kcal_burned_active": 510},
           {"date": "2026-09-18", "kcal_burned_active": 0},
           {"date": "2026-09-19", "kcal_burned_active": 660},
           {"date": "2026-09-20", "kcal_burned_active": 140},
           {"date": "2026-09-21", "kcal_burned_active": 380}
         ],
         "recommendation": "PROGRESS", "tracked_days": 6, "total_days": 7, "min_tracked_days": 5,
         "triggered_rules": [], "suggestions": []}
        """)
    }

    private var morning: MorningResponse? {
        l5Fixture(MorningResponse.self, """
        {"today_activities": [], "verdict": "GO — full session", "verdict_date": "2026-09-21",
         "carb_watch_floor": 250, "hrv_series": []}
        """)
    }

    private var dayDetail: TrainingDayDetail? {
        l5Fixture(TrainingDayDetail.self, """
        {"date": "2026-09-21",
         "activities": [{"activity_id": 1, "type": "strength", "name": "Full upper", "duration_sec": 3300, "distance_m": null}],
         "exercise_sets": [
           {"exercise_name": "Bench press", "exercise_category": null, "set_number": 1, "reps": 8, "weight_kg": 72.5},
           {"exercise_name": "Bench press", "exercise_category": null, "set_number": 2, "reps": 8, "weight_kg": 72.5},
           {"exercise_name": "Barbell row", "exercise_category": null, "set_number": 1, "reps": 10, "weight_kg": 60}
         ]}
        """)
    }

    private var exercises: [Exercise] {
        l5Fixture([Exercise].self, """
        [{"exercise_id": 11, "session_name": "Full upper A", "exercise_name": "Bench press", "sets": 4, "reps_target": "8", "current_weight_kg": 72.5, "progression_step_kg": 2.5},
         {"exercise_id": 12, "session_name": "Full upper A", "exercise_name": "Barbell row", "sets": 4, "reps_target": "10", "current_weight_kg": 60, "progression_step_kg": 2.5},
         {"exercise_id": 13, "session_name": "Full upper B", "exercise_name": "Overhead press", "sets": 3, "reps_target": "8", "current_weight_kg": 42.5, "progression_step_kg": 2.5}]
        """) ?? []
    }

    /// The fixture day's sync time, 2026-09-21 07:00 UTC (fixed so the sweep is deterministic).
    private let previewFetchedAt = Date(timeIntervalSince1970: 1_789_974_000)

    private var previewWatchLine: String? {
        #if canImport(WorkoutKit)
        trainingWatchLine(.idle)
        #else
        nil
        #endif
    }

    var body: some View {
        // B-57 W1: a ScrollView like the screen, so the sweep pins the header at the top (the
        // sweep renders through a real UIWindow now, which lays out scroll content).
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            // B-57 W1: the preview carries the screen's new header (spec §1 "Registration").
            TrainingSessionHeader(sessionName: "Full upper A", fetchedAt: previewFetchedAt, watchLine: previewWatchLine)
            TrainingDayStrip(daily: gate?.daily ?? [], selectedDate: today, today: today) { _ in }
            JISectionHeader("Readiness")
            AdaptiveHStack {
                GateDetailCard(morning: morning, gate: gate)
                Surface {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LIVE SESSION COACH").jiFont(.micro, weight: .semibold)
                            Text("Session coach").jiFont(.subheadline, weight: .bold)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
            }
            JISectionHeader("This day")
            TrainingDayDetailCard(date: today, detail: dayDetail)
            JISectionHeader("Plan")
            TrainingWeekStrip(exercises: exercises)
            LiftSteppers(exercises: exercises) { _, _ in }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .readableColumn()
        .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(JITheme.native.color(.bg))
    }
}
