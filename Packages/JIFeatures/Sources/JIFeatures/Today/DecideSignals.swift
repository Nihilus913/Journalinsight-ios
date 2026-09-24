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

// MARK: - B-57 W1 SignalRow mapping

public nonisolated struct DecideSignalRowModel: Identifiable, Equatable, Sendable {
    public let id: String, label: String, value: Double?, unit: String, decimals: Int
    public let status: JISignalStatus, detail: String?
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

/// W1 reference line: context → the hub note; sleep time → "floor X h" (unchanged floor wording,
/// spec §0.3); everything else → "threshold X unit". W3 replaces this with "your normal a–b".
public nonisolated func decideSignalRowModel(_ s: GateSignal) -> DecideSignalRowModel {
    let decimals = s.key == "sleep_h" ? 1 : 0
    let u = s.unit.isEmpty ? "" : " \(s.unit)"
    let detail: String?
    if s.status == .context { detail = gateSignalNoteText(s) }
    else if s.key == "sleep_h" { detail = "floor \(jiNumber(s.threshold, 1)) h" }
    else { detail = "threshold \(jiNumber(s.threshold, decimals))\(u)" }
    return DecideSignalRowModel(id: s.key, label: s.label, value: s.value, unit: s.unit, decimals: decimals,
                                status: decideSignalStatus(s), detail: detail)
}

/// Decide's "Why" block: one SignalRow per hub signal; tapping opens the gate rationale.
public struct DecideSignalsSection: View {
    let signals: [GateSignal]
    @Environment(\.gateRationaleModel) private var rationaleModel
    @Environment(\.gateRespondModel) private var respondModel
    @Environment(\.jiTheme) private var theme
    @State private var showRationale = false

    public init(signals: [GateSignal]) { self.signals = signals }

    private var whyHeading: some View {
        Text("Why").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
    }
    private var whyNote: some View {
        Text("your normal — \(JIMissingReason.calibrating.rawValue)").jiFont(.footnote).foregroundStyle(theme.color(.muted))
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
            ForEach(signals.map(decideSignalRowModel)) { m in
                Button { if rationaleModel != nil { showRationale = true } } label: {
                    SignalRow(label: m.label, value: m.value, unit: m.unit, decimals: m.decimals, status: m.status, detail: m.detail)
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
