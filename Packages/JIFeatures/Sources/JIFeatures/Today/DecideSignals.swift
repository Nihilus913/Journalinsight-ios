import SwiftUI
import JICore
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
    return v.formatted(.number.precision(.fractionLength(s.key == "sleep_h" ? 1 : 0)))
}

public nonisolated func gateSignalAccessibilityLabel(_ s: GateSignal) -> String {
    let thr = s.threshold.formatted(.number.precision(.fractionLength(s.key == "sleep_h" ? 1 : 0)))
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
public nonisolated func decideSignalStatus(_ s: GateSignal) -> JISignalStatus {
    guard s.value != nil else { return .missing(.noData) }
    switch s.status {
    case .pass: return .clear
    case .amber: return .watch
    case .red: return .redFlag
    case .context: return .contextOnly
    case .missing: return .missing(.noData)
    }
}

/// W-FIX3 BUG-30 (board 01): the board's names — "Resting HR", "Overnight HRV", "Daytime HRV".
/// An Apple night's "HRV (7-day)" keeps its label: it is a 7-day value, not the night's.
public nonisolated func decideSignalLabel(_ s: GateSignal) -> String {
    switch s.key {
    case "rhr": "Resting HR"
    case "hrv" where s.label == "HRV": "Overnight HRV"
    case "hrv_day": "Daytime HRV"
    default: s.label
    }
}

/// A whole number prints whole ("goal 7 h"), anything else with one decimal ("goal 6.5 h").
nonisolated func decideCompactNumber(_ v: Double) -> String { jiNumber(v, v.rounded() == v ? 0 : 1) }

/// The hub's own band in an Apple-night note ("band 41–52 ms") — that IS the normal the hub gated on.
public nonisolated func decideHubBand(_ note: String?) -> ClosedRange<Double>? {
    guard let note, let r = note.range(of: #"band\s+([0-9.]+)\s*[–-]\s*([0-9.]+)"#, options: .regularExpression) else { return nil }
    let nums = note[r].split(whereSeparator: { !($0.isNumber || $0 == ".") }).compactMap { Double($0) }
    guard nums.count == 2, nums[0] <= nums[1] else { return nil }
    return nums[0]...nums[1]
}

/// W-FIX3 BUG-30: the SignalRow reference is "your normal a–b" (spec §1) or, for sleep time, the
/// "goal 7 h" the hub gates on — never "threshold 70" / "floor 6.0 h". With no normal yet the line
/// says so ("your normal — Calibrating"); a missing value says why ("no overnight value yet").
public nonisolated func decideSignalRowModel(_ s: GateSignal, normal: ClosedRange<Double>? = nil) -> DecideSignalRowModel {
    let decimals = s.key == "sleep_h" ? 1 : 0
    var status = decideSignalStatus(s)
    var shownNormal: ClosedRange<Double>? = nil
    let detail: String?
    if s.status == .context {
        detail = gateSignalNoteText(s)
    } else if s.key == "sleep_h" {
        detail = "goal \(decideCompactNumber(s.threshold)) h"
        if s.value != nil { status = s.status == .pass ? .aboveGoal : .belowGoal }
    } else if s.value == nil {
        detail = "no overnight value yet"
    } else if let band = decideHubBand(s.note) ?? normal {
        shownNormal = band; detail = nil
    } else {
        detail = "your normal — \(JIMissingReason.calibrating.rawValue)"
    }
    return DecideSignalRowModel(id: s.key, label: decideSignalLabel(s), value: s.value, unit: s.unit, decimals: decimals,
                                status: status, detail: detail, normal: shownNormal)
}

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

/// Decide's "Why" block: one SignalRow per hub signal; tapping opens the gate rationale.
public struct DecideSignalsSection: View {
    let signals: [GateSignal]
    let normals: [String: ClosedRange<Double>]
    @Environment(\.gateRationaleModel) private var rationaleModel
    @Environment(\.gateRespondModel) private var respondModel
    @Environment(\.jiTheme) private var theme
    @State private var showRationale = false

    public init(signals: [GateSignal], normals: [String: ClosedRange<Double>] = [:]) { self.signals = signals; self.normals = normals }

    private var whyHeading: some View {
        Text("Why").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
    }
    private var whyNote: some View {
        // Board 01: "shaded = your normal" once a normal exists; until then it says it is calibrating.
        Text(normals.values.isEmpty ? "your normal — \(JIMissingReason.calibrating.rawValue)" : "compared with your normal")
            .jiFont(.footnote).foregroundStyle(theme.color(.muted))
    }

    public var body: some View {
        let rows = VStack(alignment: .leading, spacing: 8) {
            // AX sizes: the reference note drops under the heading instead of truncating to "your normal…".
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    whyHeading
                    Spacer()
                    whyNote.lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) { whyHeading; whyNote }
            }
            ForEach(signals.map { decideSignalRowModel($0, normal: normals[$0.key]) }) { m in
                Button { if rationaleModel != nil { showRationale = true } } label: {
                    SignalRow(label: m.label, value: m.value, unit: m.unit, decimals: m.decimals, normal: m.normal, status: m.status, detail: m.detail)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                }
                .buttonStyle(.pressableScale)
                .accessibilityHint(rationaleModel == nil ? "" : "Opens the readiness rationale")
                .accessibilityIdentifier("today.decide.signal.\(m.id)")
            }
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
