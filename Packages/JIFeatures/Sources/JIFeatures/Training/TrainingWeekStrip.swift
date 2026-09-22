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
/// Which plan session a week-strip row stands for: the id the assign sheet writes with, and the
/// weekday it currently shows. A pure helper so the precedence — cached spine first (it is the one
/// place an offline, still-queued assignment and a real `session_id` are recorded), exercise rows
/// second, the `exercise_id` fudge last — is testable without rendering.
nonisolated public func weekStripSession(
    named name: String, exercises: [Exercise], planSessions: [PlanSessionOut]
) -> (id: Int, weekday: Int?) {
    let rows = exercises.filter { $0.sessionName == name }
    let cached = planSessions.first { $0.name == name }
    return (
        id: cached?.id ?? rows.first?.sessionId ?? rows.first?.exerciseId ?? 0,
        weekday: cached?.weekday ?? rows.compactMap(\.weekday).first
    )
}

public struct TrainingWeekStrip: View {
    let exercises: [Exercise]
    let highlightedWeekday: Int?
    /// B-52: the view model's cached plan-session spine. When it carries a session, ITS id and
    /// weekday win — that is the one place an offline, still-queued assignment is recorded.
    /// Empty (previews, old callers) falls back to reading both off the exercise rows.
    let planSessions: [PlanSessionOut]
    /// B-52: plan-session ids whose weekday is queued but not yet accepted by the hub.
    let pendingSync: Set<Int>
    let onAssign: ((AssignWeekdaySheet.Session) -> Void)?
    @Environment(\.jiTheme) private var theme
    public init(
        exercises: [Exercise],
        highlightedWeekday: Int? = nil,
        planSessions: [PlanSessionOut] = [],
        pendingSync: Set<Int> = [],
        onAssign: ((AssignWeekdaySheet.Session) -> Void)? = nil
    ) {
        self.exercises = exercises; self.highlightedWeekday = highlightedWeekday
        self.planSessions = planSessions; self.pendingSync = pendingSync; self.onAssign = onAssign
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
        let (sessionId, weekday) = weekStripSession(named: name, exercises: exercises, planSessions: planSessions)
        let dayLabel = planWeekdayName(weekday) ?? "Not assigned"
        let isToday = weekday != nil && weekday == highlightedWeekday
        let isPending = pendingSync.contains(sessionId)
        let row = JIRow(
            title: name,
            subtitle: "\(dayLabel) · \(lifts.joined(separator: ", "))",
            systemImage: "dumbbell.fill",
            tint: isToday ? theme.color(.go) : nil
        ) {
            HStack(spacing: 6) {
                // B-52: the assignment stands on screen even though the hub hasn't taken it yet —
                // this marker is what stops that from being a lie. It clears when the drainer
                // reports the row delivered.
                if isPending {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("training.session.\(sessionId).pendingSync")
                }
                Text("\(lifts.count)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue("\(dayLabel), \(lifts.joined(separator: ", "))\(isPending ? ", waiting to sync" : "")")
        .accessibilityIdentifier("training-week-session-\(name)")

        if let onAssign {
            Button {
                onAssign(AssignWeekdaySheet.Session(id: sessionId, name: name, weekday: weekday))
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
