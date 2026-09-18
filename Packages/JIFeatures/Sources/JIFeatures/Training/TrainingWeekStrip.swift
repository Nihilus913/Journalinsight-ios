import SwiftUI
import JICore
import JIDesign

/// First-appearance-order distinct `sessionName`s (oracle: `Array.from(new Set(...))`, which is
/// also first-insertion order in JS) — a pure helper so the grouping logic is unit-testable
/// independent of the view.
nonisolated public func orderedSessionNames(_ exercises: [Exercise]) -> [String] {
    var seen = Set<String>()
    var order: [String] = []
    for e in exercises where !seen.contains(e.sessionName) { seen.insert(e.sessionName); order.append(e.sessionName) }
    return order
}

/// This-week's plan, grouped by `sessionName` (oracle: `TrainingWeekStrip.tsx`) — the hub doesn't
/// expose a weekday/session-type column, only `session_name`, so this groups by that rather than
/// fabricating a Mon–Sun grid not backed by data.
public struct TrainingWeekStrip: View {
    let exercises: [Exercise]
    public init(exercises: [Exercise]) { self.exercises = exercises }

    private var sessions: [String] { orderedSessionNames(exercises) }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Text(sessions.isEmpty ? "This week's plan" : "This week's plan · \(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold)).foregroundStyle(JIColor.muted)
                    .accessibilityAddTraits(.isHeader)
                if sessions.isEmpty {
                    Text("No plan sessions yet.").font(.footnote).foregroundStyle(JIColor.muted)
                        .accessibilityIdentifier("training-week-empty")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(sessions, id: \.self) { name in sessionCard(name) }
                        }
                    }
                }
            }
        }
    }

    private func sessionCard(_ name: String) -> some View {
        let lifts = exercises.filter { $0.sessionName == name }.map(\.exerciseName)
        return Surface(level: 2) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.footnote.weight(.bold)).foregroundStyle(JIColor.text).lineLimit(2)
                    .accessibilityLabel(name)
                Text(lifts.joined(separator: ", ")).font(.caption2).foregroundStyle(JIColor.muted).lineLimit(3)
                    .accessibilityLabel(lifts.joined(separator: ", "))
                    .accessibilityIdentifier("training-week-session-\(name)")
            }
        }
        .frame(width: 150, alignment: .leading)
    }
}
