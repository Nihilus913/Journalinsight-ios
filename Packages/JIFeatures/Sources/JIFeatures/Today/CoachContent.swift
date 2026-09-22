import Foundation
import JICore

/// B-57 §2/§6 Coach — what the Coach step says: up to three signals and one change for today.
public nonisolated struct CoachContent: Equatable, Sendable {
    public var signals: [String]
    public var change: String
    public init(signals: [String], change: String) { self.signals = signals; self.change = change }
}

/// Pure generator over the DTOs Today already holds — no clock, no hub call, invents nothing.
///
/// Signals (max 3, in order, each only when both numbers exist): newest non-nil value vs the mean
/// of the up-to-7 earlier non-nil readings — Sleep, HRV, RHR, then Load (ACWR) only if fewer than
/// three so far. Change: rest day → the rest sentence; else the hub's first suggestion; else the
/// action derived from the first triggered rule; else "Train as planned: <session>."
public nonisolated enum CoachContentBuilder {
    public static let restChange = "Rest today — mobility and a walk."

    public static func build(morning: MorningResponse?, gate: GateResponse?, recovery: [RecoveryDay],
                             locale: Locale = .autoupdatingCurrent) -> CoachContent {
        var signals: [String] = []
        if let s = compare(recovery, date: \.date, value: \.sleepScore) {
            signals.append("Sleep \(fmt(s.newest, 0, locale)) vs \(fmt(s.mean, 0, locale)) avg")
        }
        if let h = compare(morning?.hrvSeries ?? [], date: \.date, value: \.hrvWeeklyAvg) {
            signals.append("HRV \(fmt(h.newest, 0, locale)) ms vs \(fmt(h.mean, 0, locale)) avg")
        }
        if let r = compare(recovery, date: \.date, value: \.rhrBpm) {
            signals.append("RHR \(fmt(r.newest, 0, locale)) vs \(fmt(r.mean, 0, locale)) avg")
        }
        if signals.count < 3, let l = compare(recovery, date: \.date, value: \.acwr, window: nil) {
            signals.append("Load \(fmt(l.newest, 2, locale)) (last month \(fmt(l.mean, 1, locale)))")
        }
        return CoachContent(signals: Array(signals.prefix(3)), change: change(morning: morning, gate: gate))
    }

    private static func change(morning: MorningResponse?, gate: GateResponse?) -> String {
        let verdict = verdictParts(morning?.verdict)
        if morning?.verdict != nil, TodayMorningFlow.isRestDay(verdict) { return restChange }
        if let gate {
            if let suggestion = gate.suggestions.first { return suggestion }
            if !gate.triggeredRules.isEmpty {
                let action = GateHumanizeRule.capitalizeFirst(InsightSentence.actionForTriggeredRules(gate))
                return action.hasSuffix(".") ? action : action + "."
            }
        }
        // `verdictParts(nil)` carries a "No verdict yet" placeholder session — never quote it.
        let session = morning?.verdict == nil ? "" : verdict.session
        return session.isEmpty ? "Train as planned." : "Train as planned: \(session)."
    }

    /// Newest non-nil reading vs the mean of the earlier non-nil readings (the 7 before it, or all
    /// of them when `window == nil`). `nil` when either side is missing.
    private static func compare<T>(_ rows: [T], date: (T) -> String, value: (T) -> Double?,
                                   window: Int? = 7) -> (newest: Double, mean: Double)? {
        let readings = rows.sorted { date($0) > date($1) }.compactMap(value)
        guard let newest = readings.first else { return nil }
        let earlier = readings.dropFirst()
        let prior = window.map { Array(earlier.prefix($0)) } ?? Array(earlier)
        guard !prior.isEmpty else { return nil }
        return (newest, prior.reduce(0, +) / Double(prior.count))
    }

    private static func fmt(_ n: Double, _ decimals: Int, _ locale: Locale) -> String {
        GateHumanizeRule.fmt(n, decimals, locale: locale)
    }
}
