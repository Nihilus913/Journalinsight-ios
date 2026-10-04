import Foundation

/// B-57 §0.2: why a value is not shown. Rendered as "—" + this word, never as a zero.
public nonisolated enum JIMissingReason: String, Sendable, CaseIterable, Equatable {
    case calibrating = "Calibrating"
    case noData = "No data"
    case notInHealthYet = "Not in Health yet"
}

/// B-57 §1: the status word a `SignalRow` / square carries — tinted AND worded (never colour alone).
/// `clear` / `watch` / `redFlag` are the hub's pass / amber / red in words (W1: no personal normal
/// yet); the normal/goal cases go live in W2 (goals) and W3 (normals).
public nonisolated enum JISignalStatus: Sendable, Equatable {
    case aboveGoal, belowGoal, onGoal, inNormal, belowNormal, aboveNormal
    case clear, watch, redFlag
    case contextOnly
    /// W-B91 S1 (Bevel gap BP-11): the training-load (ACWR) status words (Toby Q2: over 1.30 reads "Overreaching").
    case maintaining, productive, overreaching, paused
    case missing(JIMissingReason)

    public var word: String {
        switch self {
        case .aboveGoal: "Above goal"
        case .belowGoal: "Below goal"
        case .onGoal: "On goal"
        case .inNormal: "In your normal"
        case .belowNormal: "Below your normal"
        case .aboveNormal: "Above your normal"
        case .clear: "Clear"
        case .watch: "Watch"
        case .redFlag: "Red flag"
        case .contextOnly: "Context only"
        case .maintaining: "Maintaining"
        case .productive: "Productive"
        case .overreaching: "Overreaching"
        case .paused: "Paused"
        case .missing(let reason): reason.rawValue
        }
    }

    public var role: JIColorRole {
        switch self {
        case .aboveGoal, .onGoal, .inNormal, .clear, .productive: .go
        case .belowGoal, .belowNormal, .aboveNormal, .watch, .overreaching: .reduced
        case .redFlag: .danger
        case .contextOnly, .missing, .maintaining, .paused: .muted
        }
    }

    public var symbolName: String {
        switch self {
        case .aboveGoal, .onGoal, .inNormal, .clear: "checkmark"
        case .belowGoal, .belowNormal: "arrow.down"
        case .aboveNormal: "arrow.up"
        case .watch: "exclamationmark"
        case .redFlag: "xmark"
        case .contextOnly: "info.circle"
        case .productive: "checkmark"
        case .maintaining: "arrow.down"
        case .overreaching: "arrow.up"
        case .paused: "pause"
        case .missing: "minus"
        }
    }
}

/// Locale-free fixed decimals ("27.5"), so copy and tests agree on every device.
public nonisolated func jiNumber(_ value: Double, _ decimals: Int) -> String {
    String(format: "%.\(max(0, decimals))f", value)
}

/// "—" for a missing value (rule 5); a real value at the metric's precision.
public nonisolated func jiValueText(_ value: Double?, decimals: Int) -> String {
    guard let value, value.isFinite else { return "—" }
    return jiNumber(value, decimals)
}

/// Grouped fixed decimals ("1,850", "27.5") for large hero figures — same fixed en_GB grouping as the
/// Targets captions, so a square's value and its "goal 1,617" line read alike (W-TGT r3).
public nonisolated func jiGroupedNumber(_ value: Double, _ decimals: Int) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.numberStyle = .decimal
    f.usesGroupingSeparator = true
    f.minimumFractionDigits = max(0, decimals)
    f.maximumFractionDigits = max(0, decimals)
    return f.string(from: NSNumber(value: value)) ?? jiNumber(value, decimals)
}

/// Rule 5 for text-only cells (tables, list rows): a real value with its unit, or "—" plus exactly
/// one reason word ("— No data") — never a bare dash.
public nonisolated func jiValueOrReasonText(_ value: Double?, decimals: Int, unit: String? = nil,
                                            reason: JIMissingReason = .noData) -> String {
    guard let value, value.isFinite else { return "— \(reason.rawValue)" }
    let number = jiNumber(value, decimals)
    guard let unit, !unit.isEmpty else { return number }
    return "\(number) \(unit)"
}
