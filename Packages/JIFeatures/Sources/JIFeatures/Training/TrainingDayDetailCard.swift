import SwiftUI
import JICore
import JIDesign

/// W-FIX7 fixer: the card is empty only when the hub logged nothing AND Health has no workout today.
public nonisolated func trainingDayDetailIsEmpty(detail: TrainingDayDetail?, healthWorkouts: [TodayWorkout]) -> Bool {
    (detail?.activities ?? []).isEmpty && (detail?.exerciseSets ?? []).isEmpty && healthWorkouts.isEmpty
}

/// The selected day's activities + logged sets (oracle: `TrainingDayDetailCard.tsx`), the
/// Training-side counterpart to Nutrition's meal timeline. `detail == nil` (loading / offline with
/// nothing cached) renders the same empty copy as a genuinely empty `{activities: [], exercise_sets: []}`
/// — never a false negative.
public struct TrainingDayDetailCard: View {
    let date: String
    let detail: TrainingDayDetail?
    /// B-45 (b): what the PLAN says for this weekday, next to what was actually logged. Nil when
    /// the hub has no `plan_session` for the day (or predates the field) — the card then reads
    /// exactly as it did before rather than inventing a session.
    let plannedSession: PlannedSession?
    /// W-FIX7 fixer: today's Apple Health workouts (the ones that mark the session done) — listed
    /// here, so the card never says "No training logged" beside "Done". Empty for any other day.
    let healthWorkouts: [TodayWorkout]
    @Environment(\.jiTheme) private var theme
    public init(date: String, detail: TrainingDayDetail?, plannedSession: PlannedSession? = nil, healthWorkouts: [TodayWorkout] = []) {
        self.date = date; self.detail = detail; self.plannedSession = plannedSession; self.healthWorkouts = healthWorkouts
    }

    private struct SetGroup: Identifiable { let id: String; let label: String; let sets: [DayExerciseSet] }

    private var groups: [SetGroup] {
        var order: [String] = []
        var buckets: [String: [DayExerciseSet]] = [:]
        for s in detail?.exerciseSets ?? [] {
            let key = s.exerciseName ?? s.exerciseCategory ?? "Exercise"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(s)
        }
        return order.map { SetGroup(id: $0, label: $0, sets: buckets[$0] ?? []) }
    }

    public var body: some View {
        // W-FIX10 R-02: in the order they happened (start time), not the hub's activity_id order.
        let activities = completedWorkoutsInStartOrder(detail?.activities ?? [])
        // W-B81 A-5: the hub's rows win — a Health workout the uploader already delivered is not listed twice.
        let healthWorkouts = healthWorkoutsNotOnHub(self.healthWorkouts, hub: activities)
        let isEmpty = trainingDayDetailIsEmpty(detail: detail, healthWorkouts: healthWorkouts)
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Text(formattedDate).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("training-day-detail-date")
                if let plannedSession {
                    JIRow(title: plannedSession.name, subtitle: "Planned session", systemImage: "calendar", tint: theme.color(.info)) { EmptyView() }
                        .accessibilityLabel("Planned session \(plannedSession.name)")
                        .accessibilityIdentifier("training-day-planned-session")
                    Divider().overlay(theme.color(.hairlineNested))
                }
                if isEmpty {
                    Text("No training logged for this day yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("training-day-detail-empty")
                } else {
                    ForEach(Array(healthWorkouts.enumerated()), id: \.offset) { idx, workout in
                        JIRow(title: workout.activityName, subtitle: workout.sourceName.map { "Apple Health · \($0)" } ?? "Apple Health",
                              systemImage: "heart.text.square", tint: theme.color(.info)) {
                            Text("\(workout.durationMinutes) min").accessibilityLabel("\(workout.durationMinutes) minutes")
                        }
                        .accessibilityIdentifier("training-day-health-workout")
                        if idx != healthWorkouts.count - 1 || !activities.isEmpty { Divider().overlay(theme.color(.hairlineNested)) }
                    }
                    // §2b.2: activities are inset-grouped rows, hairline-separated. W-B81 A-5: each
                    // completed workout (Apple dso 4 or Garmin) with duration · distance · avg HR.
                    ForEach(Array(activities.enumerated()), id: \.element.activityId) { idx, activity in
                        CompletedWorkoutRow(activity: activity).id("completed-workout-\(activity.activityId)")
                        if idx != activities.count - 1 { Divider().overlay(theme.color(.hairlineNested)) }
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(group.label) — \(group.sets.count) set\(group.sets.count == 1 ? "" : "s")")
                                .jiFont(.footnote, weight: .bold).foregroundStyle(theme.color(.text))
                            ForEach(Array(group.sets.enumerated()), id: \.offset) { idx, set in
                                HStack {
                                    Text("Set \(set.setNumber ?? idx + 1)").jiFont(.caption).foregroundStyle(theme.color(.muted))
                                    Spacer()
                                    Text(setSummary(set)).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.text))
                                        .accessibilityLabel("Set \(set.setNumber ?? idx + 1)")
                                        .accessibilityValue(setSummary(set))
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // B-46 item 7: cards share one width
        }
    }

    private func setSummary(_ set: DayExerciseSet) -> String {
        let reps = set.reps.map(String.init) ?? "—"
        let weight = set.weightKg.map { " × \($0.formatted())kg" } ?? ""
        return "\(reps) reps\(weight)"
    }

    private var formattedDate: String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return date }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let d = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return date }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// W-FIX10 R-02: a day's completed workouts by start time (earliest first). A row without a
/// parsable start goes last; ties and unknown starts keep the hub's `activity_id` order.
public nonisolated func completedWorkoutsInStartOrder(_ activities: [DayActivity]) -> [DayActivity] {
    activities.sorted { a, b in
        switch (a.startDate, b.startDate) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.activityId < b.activityId
        }
    }
}
