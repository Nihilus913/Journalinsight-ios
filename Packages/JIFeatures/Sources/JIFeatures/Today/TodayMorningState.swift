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

/// W-FIX2 DEV-04 (Toby 2026-09-25) — "start at the gate". The first launch after local midnight
/// opens Decide; the day view only after Go or Adjust. For regressions, `ji://gate` and the
/// launch argument `-JIForceGate YES` open Decide WITHOUT clearing today's stored call (the
/// per-verdict-date `TodayMorningFlow.prefKey` state is never written by opening the gate).
public nonisolated enum GateLaunch {
    /// `PrefStore` key holding the local calendar day (`yyyy-MM-dd`) the gate was last answered on.
    public static let lastAnsweredKey = "today.gate.lastAnsweredLocalDay"
    public static let forceArgument = "-JIForceGate"

    /// `-JIForceGate YES|TRUE|1` in the launch arguments.
    public static func forcedByArguments(_ arguments: [String]) -> Bool {
        guard let i = arguments.firstIndex(of: forceArgument), arguments.index(after: i) < arguments.endIndex else { return false }
        return ["yes", "true", "1"].contains(arguments[arguments.index(after: i)].lowercased())
    }

    /// The device's local calendar day — the gate follows the user's midnight, not the hub's.
    public static func localDay(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Decide opens when forced, or when the gate has not been answered on this local day yet.
    public static func shouldOpenGate(localDay: String, lastAnsweredLocalDay: String?, forced: Bool) -> Bool {
        forced || lastAnsweredLocalDay != localDay
    }
}
