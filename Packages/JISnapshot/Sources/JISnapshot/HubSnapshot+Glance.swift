import Foundation
import JICore

/// B-57 W5 glance vocabulary. Pure, Foundation-only, so the widget, Watch and Live Activity faces
/// render words decided here (and tested here) — the extensions have no test target.
public struct SnapshotSignal: Codable, Hashable, Sendable {
    public var key: String
    public var label: String
    public var value: Double?
    public var unit: String
    public var normalLow: Double?
    public var normalHigh: Double?
    public var goal: Double?
    /// The gate's wire status: "pass" / "amber" / "red" / "missing" / "context".
    public var status: String

    public init(key: String, label: String, value: Double?, unit: String, normalLow: Double?, normalHigh: Double?, goal: Double?, status: String) {
        self.key = key; self.label = label; self.value = value; self.unit = unit
        self.normalLow = normalLow; self.normalHigh = normalHigh; self.goal = goal; self.status = status
    }

    var decimals: Int { unit == "h" ? 1 : 0 }

    public var valueText: String { value.map { glanceNumber($0, decimals) } ?? "—" }

    /// Normal first (the band), then the goal, then the gate's own status in words.
    public var word: String {
        guard let value, status != "missing" else { return "No reading" }
        if let lo = normalLow, let hi = normalHigh {
            if value < lo { return "Low" }
            if value > hi { return "High" }
            return "In normal"
        }
        if let goal { return value >= goal ? "Enough" : "Below goal" }
        switch status {
        case "red": return "Red flag"
        case "amber": return "Caution"   // RG-87: "Watch" is the device
        case "context": return "Context"
        default: return "OK"
        }
    }

    public var caption: String {
        if value == nil || status == "missing" { return "left out" }
        if let lo = normalLow, let hi = normalHigh { return "normal \(glanceNumber(lo, decimals))–\(glanceNumber(hi, decimals))" }
        if let goal { return "goal \(glanceNumber(goal, 1)) \(unit)" }
        return "Calibrating"
    }

    // MARK: compact (the medium widget's ~48 pt columns — W-B57-W5 fixer; VoiceOver keeps the full words)

    /// "RHR" for Resting HR; the other labels are already short.
    public var shortLabel: String { key == "rhr" ? "RHR" : label }

    /// `word` in ≤ 6 characters, same meaning.
    public var compactWord: String {
        switch word {
        case "No reading": "None"
        case "In normal": "Normal"
        case "Below goal": "Short"
        case "Red flag": "Red"
        case "Context": "Info"
        default: word
        }
    }

    /// `caption` in ≤ 9 characters: the bare band ("27–30"), "goal 7.0", "left out", "no normal".
    public var compactCaption: String {
        if value == nil || status == "missing" { return "left out" }
        if let lo = normalLow, let hi = normalHigh { return "\(glanceNumber(lo, decimals))–\(glanceNumber(hi, decimals))" }
        if let goal { return "goal \(glanceNumber(goal, 1))" }
        return "no normal"
    }

    /// "HRV 25 < 27" / "RHR 62 > 56" — only when the value sits outside its normal.
    public var compactComparison: String? {
        guard let value, let lo = normalLow, let hi = normalHigh else { return nil }
        if value < lo { return "\(label) \(glanceNumber(value, decimals)) < \(glanceNumber(lo, decimals))" }
        if value > hi { return "\(label) \(glanceNumber(value, decimals)) > \(glanceNumber(hi, decimals))" }
        return nil
    }
}

/// Locale-free number text ("27.5", never "27,5").
func glanceNumber(_ v: Double, _ decimals: Int) -> String {
    String(format: "%.\(max(0, decimals))f", v)
}

public extension SnapshotKPI {
    /// "Low" / "In normal" / "High"; nil without a value or a normal (the face then says "Calibrating").
    var bandWord: String? {
        guard let value, let lo = normalLow, let hi = normalHigh else { return nil }
        return value < lo ? "Low" : (value > hi ? "High" : "In normal")
    }
    var normalCaption: String? {
        guard let lo = normalLow, let hi = normalHigh else { return nil }
        let d = (unit == "h") ? 1 : 0
        return "normal \(glanceNumber(lo, d))–\(glanceNumber(hi, d))"
    }
}

public extension HubSnapshot {
    static let reasonMaxLength = 48

    /// Trimmed, ≤ 48 characters (the 48th is "…" when clipped); blank → nil.
    static func clipReason(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard t.count > reasonMaxLength else { return t }
        return String(t.prefix(reasonMaxLength - 1)) + "…"
    }

    /// The first red signal, else the first amber one, in the gate's own order. Its note, else
    /// "<label> low" / "<label> red". Pass, context and missing signals never become a reason.
    static func reasonLine(from signals: [GateSignal]?) -> String? {
        guard let signals else { return nil }
        let pick = signals.first { $0.status == .red } ?? signals.first { $0.status == .amber }
        guard let pick else { return nil }
        let note = pick.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clipReason(note.isEmpty ? "\(pick.label) \(pick.status == .red ? "red" : "low")" : note)
    }

    var planProgressText: String? {
        guard let planTotal, planTotal > 0 else { return nil }
        return "\(planDone.map(String.init) ?? "—") of \(planTotal)"
    }

    var planFraction: Double? {
        guard let planTotal, planTotal > 0, let planDone else { return nil }
        return min(1, max(0, Double(planDone) / Double(planTotal)))
    }

    /// "Fri" from "Fri · Day 3 Full Upper".
    var nextSessionDay: String? {
        guard let nextSession, let head = nextSession.components(separatedBy: " · ").first, !head.isEmpty else { return nil }
        return head
    }

    var inlineGlanceText: String {
        if let reason { return "\(verdictWord) · \(reason)" }
        return verdictSession.isEmpty ? verdictWord : "\(verdictWord) · \(verdictSession)"
    }

    /// "cap 175" — only when the user set a cap.
    var capText: String? { hrCap.map { "cap \($0)" } }

    /// The glance slot the boards give the cap: the cap when set, else the next session's day
    /// ("next Fri"), else nothing (Toby 2026-09-24: no cap ⇒ the slot shows the next session).
    var capSlotText: String? { capText ?? nextSessionDay.map { "next \($0)" } }

    func signal(_ key: String) -> SnapshotSignal? { signals?.first { $0.key == key } }
}

/// Builds the fixed glance triple HRV · Sleep · Resting HR from the gate's signals (Garmin or
/// Apple night) plus the W3 normals and sleep goal. A signal the gate did not send is "missing" —
/// never a zero — unless `latest` holds a recent reading for that key (the gate never sends RHR,
/// W-B57-W5 fixer): it then shows as "context" (the gate did not judge it; the band still words it).
public enum GlanceSignals {
    public static func make(gateSignals: [GateSignal]?, hrvNormal: ClosedRange<Double>?, rhrNormal: ClosedRange<Double>?, sleepGoalH: Double?,
                            latest: [String: Double] = [:]) -> [SnapshotSignal] {
        let byKey = Dictionary((gateSignals ?? []).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        func one(_ key: String, label: String, unit: String, normal: ClosedRange<Double>?, goal: Double?) -> SnapshotSignal {
            let g = byKey[key]
            let status: String
            let value: Double?
            if let v = g?.value {
                value = v; status = g?.status.rawValue ?? "missing"
            } else if let v = latest[key] {
                value = v; status = "context"
            } else {
                value = nil; status = "missing"
            }
            return SnapshotSignal(key: key, label: label, value: value, unit: unit,
                                  normalLow: normal?.lowerBound, normalHigh: normal?.upperBound, goal: goal, status: status)
        }
        return [
            one("hrv", label: "HRV", unit: "ms", normal: hrvNormal, goal: nil),
            one("sleep_h", label: "Sleep", unit: "h", normal: nil, goal: sleepGoalH),
            one("rhr", label: "Resting HR", unit: "bpm", normal: rhrNormal, goal: nil),
        ]
    }
}
