import Foundation
import JICore

/// B-57 §2/§6 Coach — what the Coach step says: up to three signals and one change for today.
public nonisolated struct CoachContent: Equatable, Sendable {
    public var signals: [String]
    public var change: String
    /// W-FIX11 H1-04: the hub's own reason for an amber day ("overnight vitals not synced yet").
    public var why: String?
    public init(signals: [String], change: String, why: String? = nil) {
        self.signals = signals; self.change = change; self.why = why
    }
}

/// Pure generator over the DTOs Today already holds — no clock, no hub call, invents nothing.
///
/// Signals (max 3, in order, each only when both numbers exist): newest non-nil value vs the mean
/// of the up-to-7 earlier non-nil readings — Sleep, HRV, RHR, then Load (ACWR) only if fewer than
/// three so far. Change: rest day → the rest sentence; amber auto-regulated day → "Modified: <the
/// trimmed prescription>"; else the hub's first suggestion; else the
/// action derived from the first triggered rule; else "Train as planned: <session>."
public nonisolated enum CoachContentBuilder {
    public static let restChange = "Rest today — mobility and a walk."

    /// W-FIX11: `override` = the user's call for the verdict date (H1-03: the change line says it);
    /// `today` = the verdict day — a reading from an earlier night says its day ("(30 Sep)", H1-04);
    /// `verdictReason` = the hub's persisted reason, whose amber clause becomes `why`.
    public static func build(morning: MorningResponse?, gate: GateResponse?, recovery: [RecoveryDay],
                             override: VerdictOverride? = nil, verdictReason: String? = nil, today: String? = nil,
                             locale: Locale = .autoupdatingCurrent) -> CoachContent {
        var signals: [String] = []
        func dated(_ text: String, _ day: String) -> String {
            guard let today, day.prefix(10) < today.prefix(10), let label = dayLabel(day, locale) else { return text }
            return "\(text) (\(label))"
        }
        if let s = compare(recovery, date: \.date, value: \.sleepScore) {
            signals.append(dated("Sleep \(fmt(s.newest, 0, locale)) vs \(fmt(s.mean, 0, locale)) avg", s.day))
        }
        // W-FIX1 BUG-06: the nights' own RMSSD, never `hrv_series`' 7-day `hrv_weekly_avg` mix.
        if let h = compare(recovery, date: \.date, value: { KpiMetrics.nightlyHrvMs($0) }) {
            signals.append(dated("HRV \(fmt(h.newest, 0, locale)) ms vs \(fmt(h.mean, 0, locale)) avg", h.day))
        }
        if let r = compare(recovery, date: \.date, value: \.rhrBpm) {
            signals.append(dated("RHR \(fmt(r.newest, 0, locale)) vs \(fmt(r.mean, 0, locale)) avg", r.day))
        }
        if signals.count < 3, let l = compare(recovery, date: \.date, value: \.acwr, window: nil) {
            signals.append(dated("Load \(fmt(l.newest, 2, locale)) (last month \(fmt(l.mean, 1, locale)))", l.day))
        }
        let why = override.map { $0.choice == .accept } ?? true
            ? autoRegulatedWhy(verdictParts(morning?.verdict), reason: verdictReason) : nil
        return CoachContent(signals: Array(signals.prefix(3)), change: change(morning: morning, gate: gate, override: override), why: why)
    }

    /// "30 Sep" for a hub day key; nil when unreadable.
    private static func dayLabel(_ iso: String, _ locale: Locale) -> String? {
        let p = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        guard p.count == 3, let d = utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        return d.formatted(Date.FormatStyle(locale: locale, timeZone: utc.timeZone).day().month(.abbreviated))
    }

    private static func change(morning: MorningResponse?, gate: GateResponse?, override: VerdictOverride?) -> String {
        // W-FIX11 H1-03: the user's call (Adjust) is today's change — never the hub verdict it replaced.
        if let override, override.choice != .accept {
            switch override.choice {
            case .rest: return restChange
            default:
                let session = override.session.isEmpty
                    ? localOverrideSession(choice: override.choice, parts: verdictParts(morning?.verdict), sessionForToday: nil)
                    : override.session
                return "Your call: \(session)."
            }
        }
        let verdict = verdictParts(morning?.verdict)
        if morning?.verdict != nil, TodayMorningFlow.isRestDay(verdict) { return restChange }
        // W-FIX1 BUG-03: the hub's amber auto-regulated day is a Modified day — say the trimmed
        // session, never "Train as planned: <full session>".
        if let trimmed = autoRegulatedPrescription(verdict) {
            return "Modified: " + trimmed.prefix(1).lowercased() + trimmed.dropFirst()
        }
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
                                   window: Int? = 7) -> (newest: Double, mean: Double, day: String)? {
        let readings = rows.sorted { date($0) > date($1) }.compactMap { r in value(r).map { (date(r), $0) } }
        guard let newest = readings.first else { return nil }
        let earlier = readings.dropFirst().map(\.1)
        let prior = window.map { Array(earlier.prefix($0)) } ?? Array(earlier)
        guard !prior.isEmpty else { return nil }
        return (newest.1, prior.reduce(0, +) / Double(prior.count), newest.0)
    }

    private static func fmt(_ n: Double, _ decimals: Int, _ locale: Locale) -> String {
        GateHumanizeRule.fmt(n, decimals, locale: locale)
    }
}


// MARK: - W-GUI T4 (mockup 12): the overlay's title + note, pure

/// "One change today · 07:44" once the call has a time (the override's `createdAt` on the
/// read-only re-open); "One change today" in the morning flow. Never an invented time.
public nonisolated func coachOverlayTitle(time: String?) -> String {
    time.map { "One change today · \($0)" } ?? "One change today"
}

/// The note under the change: the signals the change cites, joined — nil when there are none
/// (the card never pads with copy).
public nonisolated func coachOverlayNote(_ content: CoachContent) -> String? {
    // W-FIX11 H1-04: the hub's reason leads ("Why: overnight vitals not synced yet").
    let parts = (content.why.map { ["Why: \($0)"] } ?? []) + content.signals
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// HH:mm of the hub timestamp in the user's zone; nil when unparseable.
public nonisolated func coachCallTime(_ createdAt: String?, timeZone: TimeZone = .autoupdatingCurrent) -> String? {
    guard let date = parseHubTimestamp(createdAt) else { return nil }
    var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
    let c = cal.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}
