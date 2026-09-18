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
    public init(date: String, detail: TrainingDayDetail?) { self.date = date; self.detail = detail }

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
                Text(formattedDate).font(.caption.weight(.semibold)).foregroundStyle(JIColor.muted)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("training-day-detail-date")
                if isEmpty {
                    Text("No training logged for this day yet.").font(.footnote).foregroundStyle(JIColor.muted)
                        .accessibilityIdentifier("training-day-detail-empty")
                } else {
                    ForEach(activities, id: \.activityId) { activity in
                        HStack {
                            Text(activity.name ?? activity.type).font(.subheadline.weight(.semibold)).foregroundStyle(JIColor.text)
                                .accessibilityLabel(activity.name ?? activity.type)
                            Spacer()
                            if let duration = activity.durationSec { Text("\(Int(duration / 60)) min").font(.footnote).foregroundStyle(JIColor.muted).accessibilityLabel("\(Int(duration / 60)) minutes") }
                        }
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(group.label) — \(group.sets.count) set\(group.sets.count == 1 ? "" : "s")")
                                .font(.footnote.weight(.bold)).foregroundStyle(JIColor.text)
                            ForEach(Array(group.sets.enumerated()), id: \.offset) { idx, set in
                                HStack {
                                    Text("Set \(set.setNumber ?? idx + 1)").font(.caption).foregroundStyle(JIColor.muted)
                                    Spacer()
                                    Text(setSummary(set)).font(.caption.weight(.semibold)).foregroundStyle(JIColor.text)
                                        .accessibilityLabel("Set \(set.setNumber ?? idx + 1)")
                                        .accessibilityValue(setSummary(set))
                                }
                            }
                        }
                    }
                }
            }
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
