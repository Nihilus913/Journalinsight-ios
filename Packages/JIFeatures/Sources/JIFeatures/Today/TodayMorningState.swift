import Foundation
import JICore

/// B-57 §2/§6 — Today's morning state. Advances on what the user does, never on the clock.
public nonisolated enum TodayMorningState: String, Codable, Sendable, Equatable { case decide, coach, day }

public nonisolated enum TodayMorningEvent: Sendable, Equatable { case gateResponded, coachAcknowledged, newVerdictDate }

public nonisolated enum TodayMorningFlow {
    public static func next(_ state: TodayMorningState, _ event: TodayMorningEvent) -> TodayMorningState {
        switch (state, event) {
        case (_, .newVerdictDate): .decide
        case (.decide, .gateResponded): .coach
        case (.coach, .coachAcknowledged): .day
        default: state
        }
    }

    /// The `PrefStore` key the reached state is kept under — one per verdict date (§2 rules).
    public static func prefKey(verdictDate: String) -> String { "today.morning.\(verdictDate)" }

    /// §2: a REST verdict has Go as its only action.
    public static func isRestDay(_ verdict: VerdictParts) -> Bool {
        verdict.word.uppercased().hasPrefix("REST")
    }
}
