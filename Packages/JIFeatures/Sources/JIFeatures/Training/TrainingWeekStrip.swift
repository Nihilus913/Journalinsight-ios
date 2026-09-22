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

/// This-week's plan, grouped by `sessionName` (oracle: `TrainingWeekStrip.tsx`). B-45: the hub
/// NOW exposes `plan_session.weekday` per row (W-B46 Contract), so each session row carries the
/// weekday it is planned for and taps through to `AssignWeekdaySheet`. A hub without the field
/// leaves `weekday == nil` and the row reads "Not assigned" — never a fabricated Mon–Sun grid.
public struct TrainingWeekStrip: View {
    let exercises: [Exercise]
    let highlightedWeekday: Int?
    let onAssign: ((AssignWeekdaySheet.Session) -> Void)?
    @Environment(\.jiTheme) private var theme
    public init(exercises: [Exercise], highlightedWeekday: Int? = nil, onAssign: ((AssignWeekdaySheet.Session) -> Void)? = nil) {
        self.exercises = exercises; self.highlightedWeekday = highlightedWeekday; self.onAssign = onAssign
    }

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
            .frame(maxWidth: .infinity, alignment: .leading)   // B-46 item 7: cards share one width
        }
    }

    @ViewBuilder
    private func sessionRow(_ name: String) -> some View {
        let rows = exercises.filter { $0.sessionName == name }
        let lifts = rows.map(\.exerciseName)
        let weekday = rows.compactMap(\.weekday).first
        let dayLabel = planWeekdayName(weekday) ?? "Not assigned"
        let isToday = weekday != nil && weekday == highlightedWeekday
        let row = JIRow(
            title: name,
            subtitle: "\(dayLabel) · \(lifts.joined(separator: ", "))",
            systemImage: "dumbbell.fill",
            tint: isToday ? theme.color(.go) : nil
        ) {
            Text("\(lifts.count)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue("\(dayLabel), \(lifts.joined(separator: ", "))")
        .accessibilityIdentifier("training-week-session-\(name)")

        if let onAssign {
            Button {
                onAssign(AssignWeekdaySheet.Session(id: rows.first?.sessionId ?? rows.first?.exerciseId ?? 0, name: name, weekday: weekday))
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityHint("Assign \(name) to a weekday")
        } else {
            row
        }
    }
}
