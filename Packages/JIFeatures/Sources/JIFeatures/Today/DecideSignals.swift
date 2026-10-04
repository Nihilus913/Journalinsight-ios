import SwiftUI
import JICore
import JICompute
import JIDesign

// MARK: - Signal helpers kept from the pre-B-57 arcs row (B-61/B-65 tests pin them)

public nonisolated func gateSignalColorRole(_ status: GateSignalStatus) -> JIColorRole {
    switch status {
    case .pass: .go
    case .amber: .reduced
    case .red: .danger
    case .missing: .nested
    case .context: .muted
    }
}

public nonisolated func gateSignalIsGating(_ s: GateSignal) -> Bool { s.status != .context }

public nonisolated func gateSignalNoteText(_ s: GateSignal) -> String? {
    guard s.status == .context, let note = s.note, !note.isEmpty else { return nil }
    return note
}

public nonisolated func gateSignalValueText(_ s: GateSignal) -> String {
    guard let v = s.value else { return "—" }
    return v.formatted(.number.precision(.fractionLength(s.key == "sleep_h" ? 1 : s.key == "load" ? 2 : 0)))
}

public nonisolated func gateSignalAccessibilityLabel(_ s: GateSignal) -> String {
    let thr = s.threshold?.formatted(.number.precision(.fractionLength(s.key == "sleep_h" ? 1 : 0))) ?? "none"
    guard s.value != nil else { return "\(s.label), not synced yet, threshold \(thr)" }
    let value = [gateSignalValueText(s), s.unit.isEmpty ? nil : s.unit].compactMap { $0 }.joined(separator: " ")
    if s.status == .context {
        return ["\(s.label) \(value), context only", gateSignalNoteText(s)].compactMap { $0 }.joined(separator: ", ")
    }
    return "\(s.label) \(value), \(s.status.rawValue), threshold \(thr)"
}

// MARK: - B-57 W1 SignalRow mapping (W-FIX3 BUG-30: board 01 wording)

public nonisolated struct DecideSignalRowModel: Identifiable, Equatable, Sendable {
    public let id: String, label: String, value: Double?, unit: String, decimals: Int
    public let status: JISignalStatus, detail: String?
    /// "your normal a–b" — the hub's own band, else the personal normal from the nights on the phone.
    public var normal: ClosedRange<Double>? = nil
}

/// The hub's per-signal verdict in words. A nil value is always "No data" (never a pass).
/// W-CAL C-4: a VALUE the hub has not judged yet (`missing` = its baseline is still calibrating) is
/// "Calibrating" beside the value — "No data" only when the value itself is null.
public nonisolated func decideSignalStatus(_ s: GateSignal) -> JISignalStatus {
    guard s.value != nil else { return .missing(.noData) }
    switch s.status {
    case .pass: return .clear
    case .amber: return .watch
    case .red: return .redFlag
    case .context: return .contextOnly
    case .missing: return .missing(.calibrating)
    }
}

/// W-CAL C-4: the row's value and its status word on one line — "27.7 ms · calibrating",
/// "31 ms · clear"; a null value is "No data".
public nonisolated func decideSignalValueLine(_ m: DecideSignalRowModel) -> String {
    guard let v = m.value, v.isFinite else { return JIMissingReason.noData.rawValue }
    // W-B91: a ratio row (Load, 2 decimals) keeps its precision — "1.84", not "1.8".
    let number = m.decimals > 1 ? jiNumber(v, m.decimals) : decideCompactNumber(v)
    let value = [number, m.unit.isEmpty ? nil : m.unit].compactMap { $0 }.joined(separator: " ")
    return "\(value) · \(m.status.word.lowercased())"
}

/// W-FIX3 BUG-30 (board 01): the board's names — "Resting HR", "Overnight HRV", "Daytime HRV",
/// sleep time "Sleep" (and the Garmin score beside it "Sleep score").
/// An Apple night's "HRV (7-day)" keeps its label: it is a 7-day value, not the night's.
public nonisolated func decideSignalLabel(_ s: GateSignal) -> String {
    switch s.key {
    case "rhr": "Resting HR"
    case "hrv" where s.label == "HRV": "Overnight HRV"
    case "hrv_day": "Daytime HRV"
    case "sleep_h": "Sleep"
    case "sleep" where s.label == "Sleep": "Sleep score"
    default: s.label
    }
}

/// A whole number prints whole ("goal 7 h"), anything else with one decimal ("goal 6.5 h").
nonisolated func decideCompactNumber(_ v: Double) -> String { jiNumber(v, v.rounded() == v ? 0 : 1) }
nonisolated func decideCompactNumber(_ v: Double?) -> String { v.map { decideCompactNumber($0) } ?? "—" }

/// W-FIX3 BUG-30: the SignalRow reference is "your normal a–b" (spec §1) or, for sleep time, the
/// "goal 7 h" the hub gates on — never "threshold 70" / "floor 6.0 h". With no normal yet the line
/// says so ("your normal — Calibrating"); a missing value says why ("no overnight value yet").
/// W-B57-W3 fixer: `recoveryNormal` is the recovery score's 28-night normal (`RecoveryInsightService`)
/// — the band the score compares a 7-day mean against, so it also applies to "HRV (7-day)" when the
/// hub's own baseline is still warming up.
/// W-TGT L3 (D2): the sleep-time goal is the user's (Targets `sleepGoalH`, nil until typed) — "goal
/// 7 h" and above/below only once typed; without one the row is the hours and the hub's own call,
/// no goal word.
public nonisolated func decideSignalRowModel(_ s: GateSignal, normal: ClosedRange<Double>? = nil,
                                             recoveryNormal: ClosedRange<Double>? = nil,
                                             sleepGoalH: Double? = nil) -> DecideSignalRowModel {
    if s.key == "load" { return decideLoadRowModel(s) }
    let decimals = s.key == "sleep_h" ? 1 : 0
    var status = decideSignalStatus(s)
    var shownNormal: ClosedRange<Double>? = nil
    let detail: String?
    if s.status == .context {
        detail = gateSignalNoteText(s)
    } else if s.key == "sleep_h" {
        if let goal = sleepGoalH {
            detail = "goal \(decideCompactNumber(goal)) h"
            if let v = s.value { status = v >= goal ? .aboveGoal : .belowGoal }
        } else {
            detail = nil
        }
    } else if s.value == nil {
        detail = "no overnight value yet"
    } else if let band = s.hubBand ?? (decideNormalApplies(s) ? normal : nil) ?? recoveryNormal {
        shownNormal = band; detail = nil
    } else if s.status == .missing, let note = s.note, !note.isEmpty {
        // W-CAL C-4: the hub says why it has no band yet ("… 15 Apple + 13 Garmin nights").
        detail = note
    } else {
        detail = "your normal — \(JIMissingReason.calibrating.rawValue)"
    }
    return DecideSignalRowModel(id: s.key, label: decideSignalLabel(s), value: s.value, unit: s.unit, decimals: decimals,
                                status: status, detail: detail, normal: shownNormal)
}

/// W-B91 S1 (Bevel gap BP-11): the hub's ACWR context row — the ratio at 2 decimals, the named
/// status word (an unknown or absent word stays "Context only"), the hub caption as the detail.
/// Never a personal-normal band: 0.80–1.30 is a population band and the caption says so.
public nonisolated func decideLoadStatus(_ s: GateSignal) -> JISignalStatus {
    guard s.value != nil else { return .missing(.noData) }
    switch s.loadStatus {
    case "maintaining": return .maintaining
    case "productive": return .productive
    case "overreaching": return .overreaching
    case "paused": return .paused
    default: return .contextOnly
    }
}

nonisolated func decideLoadRowModel(_ s: GateSignal) -> DecideSignalRowModel {
    let note = s.note.flatMap { $0.isEmpty ? nil : $0 }
    return DecideSignalRowModel(id: s.key, label: "Load", value: s.value, unit: s.unit, decimals: 2,
                                status: decideLoadStatus(s), detail: note, normal: nil)
}

/// The nightly normals describe single nights; a hub signal over another window ("HRV (7-day)")
/// only takes the hub's own band.
nonisolated func decideNormalApplies(_ s: GateSignal) -> Bool { !s.label.contains("(") }

/// W-FIX3 BUG-30 personal normal (spec §3: median ± 1.4826·MAD), display-only — the gate is the
/// hub's. `nil` until there are `minNights` real readings. Rounded to whole units.
public nonisolated func decidePersonalNormal(_ values: [Double], minNights: Int = 14) -> ClosedRange<Double>? {
    guard values.count >= minNights else { return nil }
    func median(_ xs: [Double]) -> Double {
        let s = xs.sorted(); let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
    let m = median(values)
    let spread = 1.4826 * median(values.map { abs($0 - m) })
    return (m - spread).rounded()...(m + spread).rounded()
}

/// The normals Decide and the rationale show, keyed by gate-signal key (`hrv`, `rhr`, `sleep`):
/// the up-to-28 nights BEFORE the newest one — last night is never part of its own normal.
public nonisolated func decideSignalNormals(recovery: [RecoveryDay]) -> [String: ClosedRange<Double>] {
    let prior = recovery.sorted { $0.date < $1.date }.dropLast().suffix(28)
    var out: [String: ClosedRange<Double>] = [:]
    out["hrv"] = decidePersonalNormal(prior.compactMap { KpiMetrics.nightlyHrvMs($0) })
    out["rhr"] = decidePersonalNormal(prior.compactMap(\.rhrBpm))
    out["sleep"] = decidePersonalNormal(prior.compactMap(\.sleepScore))
    return out
}

/// W-B57-W3 fixer: the recovery score's 28-night normals (Apple nights from the gate's own loader),
/// keyed by gate-signal key, rounded to whole units. Empty while calibrating.
public nonisolated func decideRecoveryNormals(hrv: PersonalNormalResult?, rhr: PersonalNormalResult?) -> [String: ClosedRange<Double>] {
    var out: [String: ClosedRange<Double>] = [:]
    for (key, n) in [("hrv", hrv), ("rhr", rhr)] {
        guard let n, n.low.isFinite, n.high.isFinite else { continue }
        let lo = n.low.rounded(), hi = n.high.rounded()
        if lo <= hi { out[key] = lo...hi }
    }
    return out
}

@MainActor func decideRecoveryNormals(_ insight: RecoveryInsightService?) -> [String: ClosedRange<Double>] {
    decideRecoveryNormals(hrv: insight?.normal(for: .hrv), rhr: insight?.normal(for: .rhr))
}

/// Decide's "Why" block: one SignalRow per hub signal; tapping opens the gate rationale.
/// W-FIX13 F-8 (B-71): the arcs the Day shows once the call is answered (Coach / Day) — the same
/// rows Decide's "What drove it" showed, so the why stays for the rest of the day. nil in Decide
/// (it shows its own) and when the hub sent no signals.
public nonisolated func dayGateArcSignals(morningState: TodayMorningState, gateSignals: [GateSignal]?) -> [GateSignal]? {
    guard morningState != .decide, let gateSignals else { return nil }
    let arcs = RecoveryScoreCard.visibleSignals(gateSignals)
    return arcs.isEmpty ? nil : arcs
}

public struct DecideSignalsSection: View {
    let signals: [GateSignal]
    let normals: [String: ClosedRange<Double>]
    @Environment(\.gateRationaleModel) private var rationaleModel
    @Environment(\.gateRespondModel) private var respondModel
    @Environment(\.recoveryInsight) private var recoveryInsight
    /// W-TGT L3: the user's sleep goal for the sleep-time row (nil until typed).
    @Environment(\.targets) private var targets
    @Environment(\.jiTheme) private var theme
    @State private var showRationale = false

    public init(signals: [GateSignal], normals: [String: ClosedRange<Double>] = [:]) { self.signals = signals; self.normals = normals }

    private var whyNote: some View {
        // Board 01: "shaded = your normal" once a normal exists; until then it says it is calibrating.
        Text(normals.values.isEmpty && decideRecoveryNormals(recoveryInsight).isEmpty ? "your normal — \(JIMissingReason.calibrating.rawValue)" : "compared with your normal")
            .jiFont(.footnote).foregroundStyle(theme.color(.muted))
    }

    public var body: some View {
        // W-GUI T1 (mockup 01): the rows live in the "What drove it" grouped card — the section
        // header is the card's, the reference note sits under it, rows are separated by hairlines.
        let recoveryNormals = decideRecoveryNormals(recoveryInsight)
        let models = signals.map { decideSignalRowModel($0, normal: normals[$0.key], recoveryNormal: recoveryNormals[$0.key],
                                                        sleepGoalH: targets?.goal(.sleep)) }
        let rows = VStack(alignment: .leading, spacing: 0) {
            whyNote.fixedSize(horizontal: false, vertical: true).padding(.vertical, JISpacing.s1)
            ForEach(Array(models.enumerated()), id: \.element.id) { index, m in
                Button { if rationaleModel != nil { showRationale = true } } label: {
                    SignalRow(label: m.label, value: m.value, unit: m.unit, decimals: m.decimals, normal: m.normal, status: m.status, detail: m.detail)
                        .padding(.vertical, JISpacing.s2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableScale)
                .accessibilityHint(rationaleModel == nil ? "" : "Opens the readiness rationale")
                .accessibilityIdentifier("today.decide.signal.\(m.id)")
                if index < models.count - 1 { JIRowDivider().padding(.leading, 0) }
            }
            if !models.isEmpty { JIRowDivider().padding(.leading, 0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.decide.signals")
        if let rationaleModel {
            rows.navigationDestination(isPresented: $showRationale) { gateRationaleScreen(model: rationaleModel, respondModel: respondModel) }
        } else {
            rows
        }
    }
}
