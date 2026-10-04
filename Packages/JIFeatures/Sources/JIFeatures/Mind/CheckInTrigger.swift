import Foundation
import JICore

// W-B102 C-1 (BP-23a, mockup docs/waves/mockups/bevel/BP-23.html): the data-triggered check-in.
// A pure predicate over the last 7 mornings — no model phrases the question and none reads the
// answer (Toby 2026-10-04: a general deterministic check-in; LLM / export-to-AI are later). The
// answer is the ordinary mind check-in; a prompt never changes the verdict, the gate or dosing.

/// The fixed rules, in priority order (one prompt a day: the first rule that holds wins).
public nonisolated enum CheckInRule: String, CaseIterable, Sendable, Codable {
    /// Verdict ≠ GO today and yesterday.
    case amber2
    /// Today's or yesterday's verdict was overridden (not "accept") and "why" was left empty.
    case overrideNoReason
    /// The last mind check-in is 3 or more days old (only after a first one exists).
    case noCheckin3

    /// Settings row title (mockup frame 04).
    public var title: String {
        switch self {
        case .amber2: "Two amber mornings"
        case .overrideNoReason: "Override without a reason"
        case .noCheckin3: "3 days without a check-in"
        }
    }

    /// Settings row caption (mockup frame 04).
    public var caption: String {
        switch self {
        case .amber2: "Verdict ≠ GO two days running"
        case .overrideNoReason: "You changed the verdict and left \"why\" empty"
        case .noCheckin3: "Counts from your last mind entry"
        }
    }
}

/// One morning of history: the hub's verdict string for that day (`plan.morning_verdict.verdict`).
public nonisolated struct CheckInMorning: Equatable, Sendable {
    public var day: DayKey
    public var verdict: String
    public init(day: DayKey, verdict: String) { self.day = day; self.verdict = verdict }

    /// "GO (auto-regulated) — …" → true; "MODIFIED — …", "REST day", "REDUCED …" → false.
    public var isGo: Bool {
        verdict.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("GO")
    }

    /// "MODIFIED — swap…" → "Modified", "REST day" → "Rest", "GO (auto-regulated) — …" → "GO".
    public var shortLabel: String {
        let head = verdict.split(separator: "—", maxSplits: 1).first.map(String.init) ?? verdict
        let bare = head.replacing(/\(.*\)/, with: "").trimmingCharacters(in: .whitespaces)
        let word = bare.split(separator: " ").first.map(String.init) ?? bare
        if word.uppercased() == "GO" { return "GO" }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }
}

/// Everything the predicate reads. Built by the app from the hub's `morningVerdict(date:)` for the
/// last 7 days, today's `/morning` override and the on-device `mind_checkin` dates.
public nonisolated struct CheckInInputs: Equatable, Sendable {
    public var today: DayKey
    /// Known mornings in the window (any order; missing days are simply absent).
    public var mornings: [CheckInMorning]
    /// The verdict override for today or yesterday, if any.
    public var override: VerdictOverride?
    /// Newest `mind_checkin.date`, nil = no check-in on this phone yet.
    public var lastCheckinDay: DayKey?
    /// The day the user tapped "Not today".
    public var snoozedDay: DayKey?
    public var enabled: Bool
    /// Gate signals of today's morning (for the "why" line; optional).
    public var gateSignals: [GateSignal]

    public init(today: DayKey, mornings: [CheckInMorning], override: VerdictOverride? = nil,
                lastCheckinDay: DayKey? = nil, snoozedDay: DayKey? = nil, enabled: Bool = true,
                gateSignals: [GateSignal] = []) {
        self.today = today; self.mornings = mornings; self.override = override
        self.lastCheckinDay = lastCheckinDay; self.snoozedDay = snoozedDay; self.enabled = enabled
        self.gateSignals = gateSignals
    }
}

/// A live prompt: the rule that fired plus its fixed, templated copy.
public nonisolated struct CheckInPrompt: Equatable, Sendable, Identifiable {
    public var rule: CheckInRule
    public var day: DayKey
    /// Notification title / Today card title.
    public var title: String
    /// Notification body / Today card text.
    public var body: String
    /// The sheet's "Why this prompt" strip.
    public var why: String
    /// The Today card's mornings line, e.g. "Modified · GO · Modified · Rest → amber ×2" (nil = none).
    public var morningsLine: String?
    public var id: String { "\(rule.rawValue)-\(day.iso)" }
}

public nonisolated enum CheckInEvaluation: Equatable, Sendable {
    case off
    case calibrating(known: Int)
    case quiet
    case prompt(CheckInPrompt)

    public var prompt: CheckInPrompt? { if case .prompt(let p) = self { p } else { nil } }
}

public nonisolated enum CheckInTrigger {
    /// The rules read this many mornings (mockup frame 05: "5 of 7 mornings").
    public static let windowDays = 7
    public static let neverChangesLine = "A check-in never changes the verdict, the gate or dosing."
    public static let storedLine = "Your answer is stored with today's date only; it does not change the verdict."

    public static func evaluate(_ inputs: CheckInInputs) -> CheckInEvaluation {
        guard inputs.enabled else { return .off }
        let today = inputs.today
        let oldest = today.adding(days: -(windowDays - 1))
        var byDay: [DayKey: CheckInMorning] = [:]
        for m in inputs.mornings where m.day >= oldest && m.day <= today { byDay[m.day] = m }
        guard byDay.count >= windowDays else { return .calibrating(known: byDay.count) }
        if inputs.snoozedDay == today || inputs.lastCheckinDay == today { return .quiet }

        let yesterday = today.adding(days: -1)
        // (a) two amber mornings
        if let t = byDay[today], let y = byDay[yesterday], !t.isGo, !y.isGo {
            return .prompt(amber2Prompt(today: t, yesterday: y, byDay: byDay, signals: inputs.gateSignals))
        }
        // (b) override without a reason
        if let o = inputs.override, o.choice != .accept,
           let day = DayKey(iso: o.date), day == today || day == yesterday,
           (o.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let when = day == today ? "this morning" : "yesterday"
            return .prompt(CheckInPrompt(
                rule: .overrideNoReason, day: today,
                title: "You changed the call \(when)",
                body: "You chose \(o.choice.rawValue.capitalized) and left \"why\" empty. How do you feel? 10 seconds.",
                why: "Verdict override on \(label(day)) (\(o.choice.rawValue.capitalized)) with no reason. \(storedLine)",
                morningsLine: nil))
        }
        // (d) three days without a check-in (never before a first one)
        if let last = inputs.lastCheckinDay, last.days(to: today) >= 3 {
            let n = last.days(to: today)
            return .prompt(CheckInPrompt(
                rule: .noCheckin3, day: today,
                title: "\(n) days without a check-in",
                body: "Your last mind check-in was \(label(last)). How do you feel? 10 seconds.",
                why: "No mind check-in since \(label(last)) (\(n) days). \(storedLine)",
                morningsLine: nil))
        }
        return .quiet
    }

    private static func amber2Prompt(today t: CheckInMorning, yesterday y: CheckInMorning,
                                     byDay: [DayKey: CheckInMorning], signals: [GateSignal]) -> CheckInPrompt {
        let flagged = signals.filter { ($0.status == .amber || $0.status == .red) && $0.value != nil }
        let evidence = flagged.prefix(2).map { s -> String in
            let v = s.value.map { Self.number($0) } ?? "—"
            let limit = s.threshold.map { " (\(s.direction == .min ? "floor" : "cap") \(Self.number($0)) \(s.unit))" } ?? ""
            return "\(s.label) \(v) \(s.unit)\(limit)"
        }
        let evidenceText = evidence.isEmpty ? "" : " " + evidence.joined(separator: ", ") + "."
        let last4 = (0..<4).reversed().compactMap { byDay[t.day.adding(days: -$0)]?.shortLabel }
        return CheckInPrompt(
            rule: .amber2, day: t.day,
            title: "Two amber mornings in a row",
            body: "\(label(y.day)) \(y.shortLabel), \(label(t.day)) \(t.shortLabel).\(evidenceText) How do you feel? 10 seconds.",
            why: "Two mornings without a GO (\(label(y.day)) \(y.shortLabel), \(label(t.day)) \(t.shortLabel)).\(evidenceText) \(storedLine)",
            morningsLine: last4.joined(separator: " · ") + " → amber ×2")
    }

    /// "Oct 3".
    static func label(_ day: DayKey) -> String { day.string(format: "MMM d") }

    static func number(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }
}
