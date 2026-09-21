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
    @Environment(\.jiTheme) private var theme
    public init(exercises: [Exercise]) { self.exercises = exercises }

    private var sessions: [String] { orderedSessionNames(exercises) }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Text(sessions.isEmpty ? "This week's plan" : "This week's plan · \(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    .accessibilityAddTraits(.isHeader)
                if sessions.isEmpty {
                    Text("No plan sessions yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("training-week-empty")
                } else {
                    // §2b.2: the horizontal card carousel becomes inset-grouped rows — one
                    // 44-pt `JIRow` per session, hairline-separated, so it reads like Health.
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element) { idx, name in
                            sessionRow(name)
                            if idx != sessions.count - 1 { Divider().overlay(theme.color(.hairlineNested)) }
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(_ name: String) -> some View {
        let lifts = exercises.filter { $0.sessionName == name }.map(\.exerciseName)
        return JIRow(title: name, subtitle: lifts.joined(separator: ", "), systemImage: "dumbbell.fill") {
            Text("\(lifts.count)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue(lifts.joined(separator: ", "))
        .accessibilityIdentifier("training-week-session-\(name)")
    }
}
