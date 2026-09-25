import Foundation
import JICompute
import JICore

// W5b-L3 (P-gate-config). The PURE half of the gate-config editor, ported from the RN oracle's
// `mobile/src/compute/configOverrides.ts` + `mobile/src/compute/gateConfigPreview.ts`.
//
// Two DIFFERENT kinds of threshold live in this feature, deliberately kept separate (RN
// `app/gate-config.tsx`'s own header makes the same split):
//
//  1. LOCAL PREVIEW overrides on the compute ports' hardcoded defaults
//     (`MorningGateConfig.default`, `JICompute.defaultKpiRules`) — this file. They sit only in
//     front of the ports and change nothing Today or Training currently show; the fixture-preview
//     card below exists to prove an override still reaches the real `evaluate()`.
//  2. LIVE server KPI targets (`GET/PUT /api/v1/planning/kpi-targets` via the existing
//     `KpiTargetsProviding`, W3b-L2) — `GateConfigViewModel`. Those edit `plan.kpi_target` rows
//     and do change the server's recommendation.
//
// Everything here is `nonisolated` (JIFeatures defaults to `MainActor` isolation — new non-UI
// declarations must opt out explicitly or off-main tests cannot call them).

// MARK: - Overridable morning-gate fields

/// `OVERRIDABLE_MORNING_GATE_FIELDS` — the numeric thresholds worth exposing as user-editable
/// overrides, in RN's order. Every other `MorningGateConfig` field is a `Set<String>`/array
/// (activity-type classification), a date (`cutStart`/`gateExperimentStart` — schedule facts) or a
/// boolean toggle (`gateExperimentActive`); none fit the "resettable numeric override" shape.
///
/// Raw values are RN's key strings verbatim so a persisted override blob has the same shape on
/// both apps.
public nonisolated enum MorningGateOverridableField: String, CaseIterable, Codable, Sendable, Hashable {
    case minSleepH = "MIN_SLEEP_H"
    case stepTarget = "STEP_TARGET"
    case kcalTarget = "KCAL_TARGET"
    case proteinTarget = "PROTEIN_TARGET"
    case carbTarget = "CARB_TARGET"
    case fatTarget = "FAT_TARGET"
    case respDeltaAmber = "RESP_DELTA_AMBER"
    case carb3dWatch = "CARB_3D_WATCH"
    case targetWeight = "TARGET_WEIGHT"
    case targetBf = "TARGET_BF"

    /// `MORNING_FIELD_META` (RN `app/gate-config.tsx`) — label, unit, stepper increment, floor.
    public var label: String {
        switch self {
        case .minSleepH: "Min sleep (interval gate)"
        case .stepTarget: "Daily steps"
        case .kcalTarget: "Display kcal target"
        case .proteinTarget: "Display protein target"
        case .carbTarget: "Display carb target"
        case .fatTarget: "Display fat target"
        case .respDeltaAmber: "Respiration amber delta"
        case .carb3dWatch: "3-day carb watch floor"
        case .targetWeight: "Cut target weight"
        case .targetBf: "Cut target body fat"
        }
    }

    public var unit: String? {
        switch self {
        case .minSleepH: "h"
        case .stepTarget: "steps"
        case .kcalTarget: "kcal"
        case .proteinTarget, .carbTarget, .fatTarget, .carb3dWatch: "g"
        case .respDeltaAmber: "breaths/min"
        case .targetWeight: "kg"
        case .targetBf: "%"
        }
    }

    public var step: Double {
        switch self {
        case .minSleepH, .respDeltaAmber, .targetWeight, .targetBf: 0.5
        case .stepTarget: 500
        case .kcalTarget: 50
        case .proteinTarget, .carbTarget, .fatTarget: 5
        case .carb3dWatch: 10
        }
    }

    /// RN gives every field `min: 0`; kept per-field so a future non-zero floor has a home.
    public var minimum: Double? { 0 }

    /// The field's value in a config. `Int`-typed constants are widened to `Double` for display and
    /// narrowed back on apply — the Python/TS types are load-bearing for verdict-string rendering
    /// (`172g` vs `172.0g`), so the narrowing must stay.
    public func value(in config: MorningGateConfig) -> Double {
        switch self {
        case .minSleepH: config.minSleepH
        case .stepTarget: Double(config.stepTarget)
        case .kcalTarget: Double(config.kcalTarget)
        case .proteinTarget: Double(config.proteinTarget)
        case .carbTarget: Double(config.carbTarget)
        case .fatTarget: Double(config.fatTarget)
        case .respDeltaAmber: config.respDeltaAmber
        case .carb3dWatch: Double(config.carb3dWatch)
        case .targetWeight: config.targetWeight
        case .targetBf: config.targetBf
        }
    }

    func apply(_ value: Double, to config: inout MorningGateConfig) {
        switch self {
        case .minSleepH: config.minSleepH = value
        case .stepTarget: config.stepTarget = Int(value.rounded())
        case .kcalTarget: config.kcalTarget = Int(value.rounded())
        case .proteinTarget: config.proteinTarget = Int(value.rounded())
        case .carbTarget: config.carbTarget = Int(value.rounded())
        case .fatTarget: config.fatTarget = Int(value.rounded())
        case .respDeltaAmber: config.respDeltaAmber = value
        case .carb3dWatch: config.carb3dWatch = Int(value.rounded())
        case .targetWeight: config.targetWeight = value
        case .targetBf: config.targetBf = value
        }
    }
}

/// B-57 W1: the GateConfig board's groups. Safety is a locked, non-field section.
public nonisolated enum GateConfigGroup: String, CaseIterable, Sendable { case safety = "Safety", recoverySignals = "Recovery signals", sleep = "Sleep", fuel = "Fuel" }

public nonisolated extension MorningGateOverridableField {
    /// nil = a display target that lives in Goals; not shown on GateConfig.
    var group: GateConfigGroup? {
        switch self {
        case .respDeltaAmber: .recoverySignals
        case .minSleepH: .sleep
        case .carb3dWatch: .fuel
        case .stepTarget, .kcalTarget, .proteinTarget, .carbTarget, .fatTarget, .targetWeight, .targetBf: nil
        }
    }
    /// B-57 W1: one plain line under each shown field (sleep stays floor-worded until W3).
    var explanation: String {
        switch self {
        case .respDeltaAmber: "Flags when your breathing rate sits this far above usual."
        case .minSleepH: "Below this, interval sessions turn Modified."
        case .carb3dWatch: "Below this for 3 days, hard sessions turn Modified."
        default: ""
        }
    }
}

/// `MorningGateOverrides` — `Partial<Record<OverridableMorningGateField, number>>`.
///
/// Backed by a `[String: Double]` rather than a keyed-by-enum dictionary on purpose: `JSONEncoder`
/// encodes a `Dictionary` whose `Key` is a `RawRepresentable` enum as an *array* of alternating
/// keys/values, which would not round-trip against RN's object-shaped blob.
public nonisolated struct MorningGateOverrides: Codable, Equatable, Sendable {
    public private(set) var values: [String: Double]

    public init(_ values: [String: Double] = [:]) { self.values = values }

    public init(from decoder: any Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: Double].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }

    public subscript(field: MorningGateOverridableField) -> Double? {
        get { values[field.rawValue] }
        set { values[field.rawValue] = newValue }
    }

    public func contains(_ field: MorningGateOverridableField) -> Bool { values[field.rawValue] != nil }

    public var isEmpty: Bool { values.isEmpty }

    /// `{ ...cur, [field]: next }`.
    public func setting(_ field: MorningGateOverridableField, to value: Double) -> MorningGateOverrides {
        var next = self
        next.values[field.rawValue] = value
        return next
    }

    /// `delete next[field]` — clears one field back to the compute port's hardcoded default.
    public func clearing(_ field: MorningGateOverridableField) -> MorningGateOverrides {
        var next = self
        next.values.removeValue(forKey: field.rawValue)
        return next
    }
}

/// `applyMorningGateOverrides` — layers `overrides` on top of `base`. A shallow field-by-field
/// apply is correct because every overridable field is a scalar.
public nonisolated func applyMorningGateOverrides(
    _ overrides: MorningGateOverrides,
    base: MorningGateConfig = .default
) -> MorningGateConfig {
    var config = base
    for field in MorningGateOverridableField.allCases {
        if let v = overrides[field] { field.apply(v, to: &config) }
    }
    return config
}

// MARK: - The bundled fixture day

/// One bundled fixture row for the gate-config editor's live preview (E12-8 acceptance: "a
/// fixture-evaluation preview in the editor shows the verdict flip"). This is NOT live data — it is
/// a fixed, hand-picked interval-day case chosen so the numbers actually move the verdict.
///
/// The JSON of record is `Fixtures/gate_config_preview_day.json` at the repo root;
/// ``GatePreviewFixture/bundled`` is the same day inline (RN keeps it inline too, and JIFeatures
/// ships no resource bundle). `GateConfigPreviewTests` decodes the JSON and asserts the two never
/// drift.
public nonisolated struct GatePreviewFixture: Codable, Equatable, Sendable {
    public struct Vitals: Codable, Equatable, Sendable {
        public var sleep: Int?
        public var sleepDurationH: Double?
        public var hrv: Int?
        public var hrvStatus: String?
        public var rhr: Int?
        public var rhrDate: String?
        public var stepsYesterday: Int?

        public init(sleep: Int?, sleepDurationH: Double?, hrv: Int?, hrvStatus: String?, rhr: Int?, rhrDate: String?, stepsYesterday: Int?) {
            self.sleep = sleep; self.sleepDurationH = sleepDurationH; self.hrv = hrv
            self.hrvStatus = hrvStatus; self.rhr = rhr; self.rhrDate = rhrDate
            self.stepsYesterday = stepsYesterday
        }

        enum CodingKeys: String, CodingKey {
            case sleep
            case sleepDurationH = "sleep_duration_h"
            case hrv
            case hrvStatus = "hrv_status"
            case rhr
            case rhrDate = "rhr_date"
            case stepsYesterday = "steps_yesterday"
        }

        public var morningVitals: MorningVitals {
            MorningVitals(
                sleep: sleep, sleepDurationH: sleepDurationH, hrv: hrv, hrvStatus: hrvStatus,
                rhr: rhr, rhrDate: rhrDate, stepsYesterday: stepsYesterday
            )
        }
    }

    public var today: String
    public var vitals: Vitals
    public var dosedDates: [String]

    public init(today: String, vitals: Vitals, dosedDates: [String] = []) {
        self.today = today; self.vitals = vitals; self.dosedDates = dosedDates
    }

    enum CodingKeys: String, CodingKey {
        case today, vitals
        case dosedDates = "dosed_dates"
    }

    /// `GATE_PREVIEW_FIXTURE`. 2026-08-25 is a Tuesday — `sessionByWeekday[1]` = "Norwegian 4x4
    /// intervals", an interval day — with `sleepDurationH` 6.2. Under the default config
    /// (`minSleepH` 6.0) 6.2 >= 6.0 passes and every other interval-gate check (sleep >= 70,
    /// hrv >= 27, rhr <= 65) passes too, so the verdict is "GO — Norwegian 4x4 intervals". Raising
    /// `minSleepH` past 6.2 fails `dur >= config.minSleepH` inside `evaluate()` and flips it to
    /// "MODIFIED — swap intervals for easy Z2 30-40min".
    public static let bundled = GatePreviewFixture(
        today: "2026-08-25",
        vitals: Vitals(
            sleep: 75, sleepDurationH: 6.2, hrv: 35, hrvStatus: nil,
            rhr: 58, rhrDate: "2026-08-24", stepsYesterday: 15500
        ),
        dosedDates: []
    )
}

/// `GatePreviewResult`.
public nonisolated struct GatePreviewResult: Equatable, Sendable {
    public var verdict: String
    public var conditions: [String]

    public init(verdict: String, conditions: [String]) {
        self.verdict = verdict; self.conditions = conditions
    }
    /// W-FIX1 BUG-27 (W1 carryover): the preview as the user reads it — "Full · Norwegian 4x4
    /// intervals", "Modified · swap intervals for easy Z2 30-40min" — never the hub's "GO — …".
    /// `verdict` stays raw: it is what `evaluate()` returned and what the flip compares.
    public var displayVerdict: String {
        let parts = verdictParts(verdict)
        let word = verdictUserWord(parts)
        return parts.session.isEmpty ? word : "\(word) · \(parts.session)"
    }
}

/// `previewMorningGateVerdict` — runs the REAL `JICompute.evaluate()` against the bundled fixture
/// day under `overrides` (layered on `MorningGateConfig.default`). PREVIEW ONLY: nothing here
/// touches Today or Training.
///
/// `evaluate` is `throws` in the Swift port (`CalendarMath.isoWeekday` rejects a malformed date);
/// the fixture day is a compile-time constant so the failure is impossible for `.bundled`, but the
/// signature stays honest for a caller that passes its own day.
public nonisolated func previewMorningGateVerdict(
    _ overrides: MorningGateOverrides,
    fixture: GatePreviewFixture = .bundled
) throws -> GatePreviewResult {
    let config = applyMorningGateOverrides(overrides)
    let result = try evaluate(
        today: fixture.today,
        vitals: fixture.vitals.morningVitals,
        db: MorningGateDb(),
        state: MorningGatePrevState(),
        dosedDates: fixture.dosedDates,
        config: config
    )
    return GatePreviewResult(verdict: result.verdict, conditions: result.conditions)
}

// MARK: - KPI gate rules (local preview overrides)

/// `kpiRuleKey` — a stable key for one `defaultKpiRules` row. `metric` alone is not unique
/// ("acwr" appears three times at different operators) but `metric:operator` is.
public nonisolated func kpiRuleKey(metric: String, operator op: String) -> String { "\(metric):\(op)" }

public nonisolated func kpiRuleKey(_ rule: KpiRule) -> String {
    kpiRuleKey(metric: rule.metric, operator: rule.operator)
}

/// `KpiRuleOverride` — only `threshold`/`thresholdHi` are overridable; the rule's structure
/// (`metric`/`operator`/`description`) stays fixed, the same contract the server's
/// `update_kpi_target` enforces.
public nonisolated struct KpiRuleOverride: Codable, Equatable, Sendable {
    public var threshold: Double?
    public var thresholdHi: Double?

    public init(threshold: Double? = nil, thresholdHi: Double? = nil) {
        self.threshold = threshold; self.thresholdHi = thresholdHi
    }

    enum CodingKeys: String, CodingKey {
        case threshold
        case thresholdHi = "threshold_hi"
    }
}

/// `KpiRuleOverrides` — `Record<string, KpiRuleOverride>`, keyed by ``kpiRuleKey(_:)``.
public nonisolated struct KpiRuleOverrides: Codable, Equatable, Sendable {
    public private(set) var values: [String: KpiRuleOverride]

    public init(_ values: [String: KpiRuleOverride] = [:]) { self.values = values }

    public init(from decoder: any Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: KpiRuleOverride].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }

    public subscript(key: String) -> KpiRuleOverride? { values[key] }

    public func contains(_ key: String) -> Bool { values[key] != nil }

    /// `{ ...current, [key]: { ...current[key], ...patch } }` — a shallow per-field merge, so
    /// patching only `threshold` leaves an existing `thresholdHi` override in place.
    public func setting(_ key: String, threshold: Double? = nil, thresholdHi: Double? = nil) -> KpiRuleOverrides {
        var next = self
        var entry = values[key] ?? KpiRuleOverride()
        if let threshold { entry.threshold = threshold }
        if let thresholdHi { entry.thresholdHi = thresholdHi }
        next.values[key] = entry
        return next
    }

    public func clearing(_ key: String) -> KpiRuleOverrides {
        var next = self
        next.values.removeValue(forKey: key)
        return next
    }
}

/// `applyKpiRuleOverrides` — layers `overrides` on top of `base`, preserving rule structure.
public nonisolated func applyKpiRuleOverrides(
    _ overrides: KpiRuleOverrides,
    base: [KpiRule] = defaultKpiRules
) -> [KpiRule] {
    base.map { rule in
        guard let o = overrides[kpiRuleKey(rule)] else { return rule }
        var next = rule
        next.threshold = o.threshold ?? rule.threshold
        next.thresholdHi = o.thresholdHi ?? rule.thresholdHi
        return next
    }
}

// MARK: - Display

/// `fmtNum` — integers render bare, everything else to one decimal.
public nonisolated func gateConfigFormat(_ v: Double) -> String {
    v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(format: "%.1f", v)
}

/// The stepper increment RN uses for a KPI rule row: 0.05 for `acwr`, 25 for the kcal averages,
/// 5 otherwise.
public nonisolated func kpiRuleStep(metric: String) -> Double {
    if metric == "acwr" { return 0.05 }
    if metric.hasPrefix("avg_kcal") { return 25 }
    return 5
}
