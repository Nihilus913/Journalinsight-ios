import SwiftUI
import JICore
import JIDesign
import JIWorkouts

/// W-B38-B B-8 — the sets logged on the Watch as they land (`SessionCoach.dc.html`: exercise ·
/// set n of N, kg × reps, the set list with the current one marked, Next exercise).
struct MirroredSetsCard: View {
    let feed: MirroredSessionFeed
    private let theme = JITheme.native

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 8) {
                if let key = feed.currentExerciseKey {
                    let done = feed.sets(for: key)
                    let planned = feed.plannedSets(key)
                    Text(mirroredHeader(name: feed.exerciseName(key), logged: done.count, planned: planned))
                        .jiFont(.micro, weight: .semibold).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("session-coach-mirror-header")
                    if done.isEmpty {
                        Text("No set logged yet — log one on your Watch.").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    }
                    ForEach(Array(done.enumerated()), id: \.element.clientId) { i, set in
                        HStack {
                            Text("Set \(i + 1)").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                            Spacer()
                            Text(mirroredSetText(set)).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.text))
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let next = nextExercise(after: key) {
                        Text("Next: \(next)").jiFont(.caption).foregroundStyle(theme.color(.muted))
                    }
                } else {
                    Text("Sets you log on your Watch show here.").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("session-coach-mirrored-sets")
    }

    private func nextExercise(after key: String) -> String? {
        guard let list = feed.plan?.exercises, let i = list.firstIndex(where: { $0.exerciseKey == key }), i + 1 < list.count else { return nil }
        return list[i + 1].name
    }
}

/// "BENCH PRESS · SET 2 OF 3" — the set being worked is the next after those logged.
nonisolated func mirroredHeader(name: String, logged: Int, planned: Int?) -> String {
    let n = planned.map { min(logged + 1, $0) } ?? logged + 1
    let of = planned.map { " OF \($0)" } ?? ""
    return "\(name.uppercased()) · SET \(n)\(of)"
}

/// "52.5 kg × 8", "45 s", "8 reps" — absent fields are omitted, never zero.
nonisolated func mirroredSetText(_ s: StrengthBridgeSet) -> String {
    StrengthSessionActivityState(exercise: s.exerciseKey, setNumber: s.setIndex, weightKg: s.weightKg, reps: s.reps,
                                 durationS: s.kind == .timed ? s.durationS : nil, updatedAt: s.performedAt).loadLine ?? "Logged"
}
