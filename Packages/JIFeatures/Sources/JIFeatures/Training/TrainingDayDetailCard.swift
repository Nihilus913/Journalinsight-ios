import SwiftUI
import JICore
import JIDesign

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
    @Environment(\.jiTheme) private var theme
    public init(date: String, detail: TrainingDayDetail?, plannedSession: PlannedSession? = nil) {
        self.date = date; self.detail = detail; self.plannedSession = plannedSession
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
        let activities = detail?.activities ?? []
        let isEmpty = activities.isEmpty && groups.isEmpty
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
                    // §2b.2: activities are 44-pt inset-grouped rows, hairline-separated.
                    ForEach(Array(activities.enumerated()), id: \.element.activityId) { idx, activity in
                        JIRow(title: activity.name ?? activity.type, systemImage: "figure.run", tint: theme.color(.info)) {
                            if let duration = activity.durationSec {
                                Text("\(Int(duration / 60)) min").accessibilityLabel("\(Int(duration / 60)) minutes")
                            }
                        }
                        .accessibilityLabel(activity.name ?? activity.type)
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
