import Foundation

// W-TGT L1 — spec §5: the one-shot import of today's stores into `TargetsDocument`. Pure: the
// store (`TargetsStore.migrateIfNeeded`, JIPersistence) reads the rows and hands them here.
// No value changes, no seeding: every number comes from a stored row; missing = nil.

/// `gate.settings` as stored by `GateSettingsStore` (JIFeatures `GateSettings`), read tolerantly
/// field by field. No explicit CodingKeys: `PrefStore` round-trips through `JSON.encoder/decoder`.
public nonisolated struct LegacyGateSettings: Codable, Equatable, Sendable {
    public var preset: String?
    public var hrCapBpm: Int?
    public var avoidZone5: Bool
    public var zones: HrZones?
    public var hrCapConfirmedOn: String?

    public init(preset: String?, hrCapBpm: Int?, avoidZone5: Bool, zones: HrZones?, hrCapConfirmedOn: String?) {
        self.preset = preset; self.hrCapBpm = hrCapBpm; self.avoidZone5 = avoidZone5
        self.zones = zones; self.hrCapConfirmedOn = hrCapConfirmedOn
    }

    enum CodingKeys: String, CodingKey { case preset, hrCapBpm, avoidZone5, zones, hrCapConfirmedOn }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = c.lenient(String.self, .preset)
        hrCapBpm = c.lenient(Int.self, .hrCapBpm)
        avoidZone5 = c.lenient(Bool.self, .avoidZone5) ?? false
        zones = c.lenient(HrZones.self, .zones).flatMap { $0.isValid ? $0 : nil }
        hrCapConfirmedOn = c.lenient(String.self, .hrCapConfirmedOn)
    }

    /// `GatePreset.hrvLowNights` (cautious 1 · balanced 2 · push 3); unknown = nil (recommended).
    public var hrvLowNights: Int? {
        switch preset { case "cautious": 1; case "balanced": 2; case "push": 3; default: nil }
    }
}

/// One `config_overrides.kpi_rules` entry (preview-only; read once and discarded).
public nonisolated struct LegacyKpiRuleOverride: Codable, Equatable, Sendable {
    public var threshold: Double?
    public var thresholdHi: Double?
    public init(threshold: Double?, thresholdHi: Double?) { self.threshold = threshold; self.thresholdHi = thresholdHi }
}

/// Everything the phone holds today (spec §1 G1–G5, L1–L2, R1–R4). nil = the row is absent.
public nonisolated struct TargetsLegacySources: Equatable, Sendable {
    /// PrefStore `goals.macros` (G4, G5).
    public var macros: MacroGoals?
    /// PrefStore `gate.settings` (L1, L2, R1).
    public var gateSettings: LegacyGateSettings?
    /// PrefStore `config_overrides.morning_gate` (R2, R3).
    public var morningOverrides: [String: Double]?
    /// PrefStore `config_overrides.kpi_rules` (preview-only copy of R4).
    public var kpiRuleOverrides: [String: LegacyKpiRuleOverride]?
    /// OfflineCache `kpi.targets` — the hub's `plan.kpi_target` rows (R4).
    public var kpiTargets: [KpiTarget]?
    /// `goal_targets_mirror` — the cached `/planning/goals` document (G1–G3).
    public var hubGoals: Goals?

    public init(macros: MacroGoals? = nil, gateSettings: LegacyGateSettings? = nil,
                morningOverrides: [String: Double]? = nil, kpiRuleOverrides: [String: LegacyKpiRuleOverride]? = nil,
                kpiTargets: [KpiTarget]? = nil, hubGoals: Goals? = nil) {
        self.macros = macros; self.gateSettings = gateSettings; self.morningOverrides = morningOverrides
        self.kpiRuleOverrides = kpiRuleOverrides; self.kpiTargets = kpiTargets; self.hubGoals = hubGoals
    }
}

public nonisolated struct TargetsImportResult: Equatable, Sendable {
    public var document: TargetsDocument
    /// One line per value read and NOT imported (hidden overrides, preview-only rules, unknown rows).
    public var discarded: [String]

    public init(document: TargetsDocument, discarded: [String]) { self.document = document; self.discarded = discarded }
}

public nonisolated enum TargetsImporter {
    /// R2 `config_overrides.morning_gate` fields that ARE rules.
    static let overrideRules: [String: RuleMetric] = [
        "RESP_DELTA_AMBER": .respDeltaAmber, "CARB_3D_WATCH": .carbThreeDayFloor, "MIN_SLEEP_H": .intervalMinSleep,
    ]

    public static func makeDocument(from s: TargetsLegacySources) -> TargetsImportResult {
        var doc = TargetsDocument.empty
        var discarded: [String] = []

        // 1. Goals ← goals.macros as-is; weight/date/steps/strength ← cached /planning/goals.
        if let macros = s.macros { doc.macroGoals = macros }
        if let hub = s.hubGoals {
            doc.goals.weight = WeightTarget(baseKg: hub.weight.baseKg, targetKg: hub.weight.targetKg, targetDate: hub.weight.targetDate)
            doc.goals.stepsDaily = hub.stepsDaily
            doc.goals.strength = hub.strength
        }

        // 2. Limits ← gate.settings verbatim; preset → rule hrvLowNights.
        if let g = s.gateSettings {
            doc.limits = TargetLimits(hrCapBpm: g.hrCapBpm, hrCapConfirmedOn: g.hrCapConfirmedOn, zones: g.zones, avoidZone5: g.avoidZone5)
            doc.rules[.hrvLowNights] = g.hrvLowNights.map(Double.init)
        }

        // 3a. Rules ← config_overrides.morning_gate, only what was overridden. The hidden R3
        //     overrides are never sources: the goal (the shown number) wins; log what is dropped.
        for (key, value) in (s.morningOverrides ?? [:]).sorted(by: { $0.key < $1.key }) {
            if let rule = overrideRules[key] {
                doc.rules[rule] = value
            } else {
                discarded.append("config_overrides.morning_gate.\(key)=\(format(value)) (hidden override; not a source)")
            }
        }

        // 3b. Rules ← plan.kpi_target rows with their current numbers.
        for row in s.kpiTargets ?? [] {
            let matches = RuleMetric.allCases.filter { $0.kpiTargetRow?.metric == row.metric && $0.kpiTargetRow?.op == row.operator }
            guard !matches.isEmpty else {
                discarded.append("kpi.targets#\(row.targetId) \(row.metric) \(row.operator) \(format(row.threshold)) (unknown rule)")
                continue
            }
            for rule in matches {
                let value = rule.kpiTargetRow?.hi == true ? row.thresholdHi : row.threshold
                if let value { doc.rules[rule] = value }
            }
        }

        // 3c. config_overrides.kpi_rules was a preview-only copy: read once, discarded.
        for (key, o) in (s.kpiRuleOverrides ?? [:]).sorted(by: { $0.key < $1.key }) {
            let parts = [o.threshold.map { "threshold=\(format($0))" }, o.thresholdHi.map { "threshold_hi=\(format($0))" }].compactMap { $0 }
            discarded.append("config_overrides.kpi_rules.\(key) \(parts.joined(separator: " ")) (preview-only; not a source)")
        }

        return TargetsImportResult(document: doc, discarded: discarded)
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
