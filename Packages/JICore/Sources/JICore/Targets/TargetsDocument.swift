import Foundation

// W-TGT (spec HT docs/superpowers/specs/2026-09-28-targets-alignment-design.md §3) — ONE document
// the phone owns for every user-set target: Goals (what I aim for), Limits (what I never exceed),
// Rules (how the call is made). PrefStore key `targets.v1` (`TargetsStore`), mirrored to the hub
// as ONE body (`PUT /api/v1/planning/targets`, outbox kind `targets`).
//
// FROZEN SHAPE (the hub codes against it). Wire = `JSON.encoder` output, snake_case keys, every
// key below always present, unset = null:
// {
//   "version": 1,
//   "goals":  { "weight": {"base_kg","target_kg","target_date"} | null,
//               "kcal":   {"goal_kcal","basis":"includes_deficit"|"subtract_deficit",
//                          "deficit_kcal_per_day","weekly_loss_kg","target_kcal"} | null,
//               "protein_g","carbs_g","fat_g","steps_daily"(int),"sleep_h",
//               "strength": [{"exercise","target_kg"}] },
//   "limits": { "hr_cap_bpm"(int),"hr_cap_confirmed_on"("yyyy-MM-dd"),
//               "zones": {"anchor":"maxHr"|"lthr","anchor_bpm","floors_bpm":[5 ascending ints]} | null,
//               "avoid_zone5": bool },
//   "rules":  { "hrv_low_nights"(int),"resp_delta_amber","carb_three_day_floor","interval_min_sleep",
//               "load_over","load_under","load_band_low","load_band_high",
//               "week_kcal_floor","week_protein_floor","week_sleep_score_floor" }   // null = recommended
// }
// `target_kcal` is derived (goal − deficit), written for the hub, ignored on decode.
//
// Invariants: one number per (metric, kind); Goals and Limits are never seeded (nil = none);
// a Rule is nil until the user changes it and then reads its recommended value; normals are
// computed elsewhere and never stored here; nothing clinical (no HRV/RHR goal or limit).

public nonisolated enum TargetKind: String, Codable, CaseIterable, Sendable { case goal, limit, rule }

public nonisolated enum GoalMetric: String, CaseIterable, Sendable {
    case weight, kcal, protein, carbs, fat, steps, sleep
}

public nonisolated enum LimitMetric: String, CaseIterable, Sendable {
    case hrCap, zone5Floor
}

/// How the call is made. Each has a recommended value (today's gate constant), disclosed as
/// "recommended" until the user changes it.
public nonisolated enum RuleMetric: String, CaseIterable, Sendable {
    /// Caution preset: consecutive low-HRV nights that turn the call red (1 / 2 / 3).
    case hrvLowNights
    /// Respiration delta (breaths/min over the 14-day baseline) that reads amber.
    case respDeltaAmber
    /// 3-day carb average floor (g/day) for the glycogen watch.
    case carbThreeDayFloor
    /// Garmin nights: minimum sleep (h) for intervals.
    case intervalMinSleep
    /// `acwr > x` — REDUCE (overreaching).
    case loadOver
    /// `acwr < x` — MAINTAIN (undertraining).
    case loadUnder
    /// `acwr between low–high` — PROGRESS zone.
    case loadBandLow, loadBandHigh
    /// `avg_kcal_7d < x`, `avg_protein_7d < x`, `sleep_score_7d < x` — REDUCE floors.
    case weekKcalFloor, weekProteinFloor, weekSleepScoreFloor

    /// Today's constants: `plan.kpi_target` seeds (hub migrations 003/004, JICompute
    /// `defaultKpiRules`) and `morning_go` / `MorningGateConfig.default`.
    public var recommended: Double {
        switch self {
        case .hrvLowNights: 2
        case .respDeltaAmber: 2.0
        case .carbThreeDayFloor: 120
        case .intervalMinSleep: 6.0
        case .loadOver: 1.30
        case .loadUnder: 0.80
        case .loadBandLow: 0.80
        case .loadBandHigh: 1.30
        case .weekKcalFloor: 1600
        case .weekProteinFloor: 130
        case .weekSleepScoreFloor: 55
        }
    }

    public var unit: String? {
        switch self {
        case .hrvLowNights: "nights"
        case .respDeltaAmber: "breaths/min"
        case .carbThreeDayFloor, .weekProteinFloor: "g"
        case .intervalMinSleep: "h"
        case .loadOver, .loadUnder, .loadBandLow, .loadBandHigh, .weekSleepScoreFloor: nil
        case .weekKcalFloor: "kcal"
        }
    }

    /// Whole-number rules travel as JSON ints.
    public var isInteger: Bool { self == .hrvLowNights }

    /// The snake_case key on the wire / in PrefStore.
    public var wireKey: String {
        rawValue.reduce(into: "") { out, ch in
            if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
        }
    }

    /// The hub `plan.kpi_target` row this rule is (metric, operator, which threshold).
    public var kpiTargetRow: (metric: String, op: String, hi: Bool)? {
        switch self {
        case .loadOver: ("acwr", ">", false)
        case .loadUnder: ("acwr", "<", false)
        case .loadBandLow: ("acwr", "between", false)
        case .loadBandHigh: ("acwr", "between", true)
        case .weekKcalFloor: ("avg_kcal_7d", "<", false)
        case .weekProteinFloor: ("avg_protein_7d", "<", false)
        case .weekSleepScoreFloor: ("sleep_score_7d", "<", false)
        case .hrvLowNights, .respDeltaAmber, .carbThreeDayFloor, .intervalMinSleep: nil
        }
    }
}

// MARK: - Goals

public nonisolated struct WeightTarget: Codable, Equatable, Sendable {
    public var baseKg: Double?
    public var targetKg: Double?
    public var targetDate: String?

    public init(baseKg: Double? = nil, targetKg: Double? = nil, targetDate: String? = nil) {
        self.baseKg = baseKg; self.targetKg = targetKg; self.targetDate = targetDate
    }

    enum CodingKeys: String, CodingKey { case baseKg, targetKg, targetDate }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseKg = c.lenient(Double.self, .baseKg)
        targetKg = c.lenient(Double.self, .targetKg)
        targetDate = c.lenient(String.self, .targetDate)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeOrNull(baseKg, .baseKg)
        try c.encodeOrNull(targetKg, .targetKg)
        try c.encodeOrNull(targetDate, .targetDate)
    }
}

public nonisolated struct TargetGoals: Codable, Equatable, Sendable {
    public var weight: WeightTarget?
    public var kcal: KcalGoal?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var stepsDaily: Int?
    /// D2 (Toby 2026-09-28): user-typed, nil until set; never a default.
    public var sleepH: Double?
    /// Display only (auto from sessions / the hub's strength goals).
    public var strength: [StrengthGoal]

    public init(weight: WeightTarget? = nil, kcal: KcalGoal? = nil, proteinG: Double? = nil, carbsG: Double? = nil,
                fatG: Double? = nil, stepsDaily: Int? = nil, sleepH: Double? = nil, strength: [StrengthGoal] = []) {
        self.weight = weight; self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG
        self.fatG = fatG; self.stepsDaily = stepsDaily; self.sleepH = sleepH; self.strength = strength
    }

    enum CodingKeys: String, CodingKey { case weight, kcal, proteinG, carbsG, fatG, stepsDaily, sleepH, strength }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weight = c.lenient(WeightTarget.self, .weight)
        kcal = c.lenient(KcalWire.self, .kcal)?.goal
        proteinG = c.lenient(Double.self, .proteinG)
        carbsG = c.lenient(Double.self, .carbsG)
        fatG = c.lenient(Double.self, .fatG)
        stepsDaily = c.lenient(Int.self, .stepsDaily)
        sleepH = c.lenient(Double.self, .sleepH)
        strength = c.lenient([StrengthGoal].self, .strength) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeOrNull(weight, .weight)
        try c.encodeOrNull(kcal.map(KcalWire.init), .kcal)
        try c.encodeOrNull(proteinG, .proteinG)
        try c.encodeOrNull(carbsG, .carbsG)
        try c.encodeOrNull(fatG, .fatG)
        try c.encodeOrNull(stepsDaily, .stepsDaily)
        try c.encodeOrNull(sleepH, .sleepH)
        try c.encode(strength, forKey: .strength)
    }
}

/// The flat wire form of `KcalGoal` (its own Codable is the `goals.macros` storage form).
private nonisolated struct KcalWire: Codable {
    var goalKcal: Double
    var basis: String
    var deficitKcalPerDay: Double?
    var weeklyLossKg: Double?
    var targetKcal: Double?

    init(_ g: KcalGoal) {
        goalKcal = g.goalKcal; targetKcal = g.targetKcal
        switch g.basis {
        case .includesDeficit: basis = "includes_deficit"
        case .subtractDeficit(.deficit(let kcal)): basis = "subtract_deficit"; deficitKcalPerDay = kcal
        case .subtractDeficit(.weeklyLoss(let kg)): basis = "subtract_deficit"; weeklyLossKg = kg
        }
    }

    var goal: KcalGoal? {
        switch basis {
        case "includes_deficit": return KcalGoal(goalKcal: goalKcal, basis: .includesDeficit)
        case "subtract_deficit":
            if let kg = weeklyLossKg { return KcalGoal(goalKcal: goalKcal, basis: .subtractDeficit(.weeklyLoss(kgPerWeek: kg))) }
            if let kcal = deficitKcalPerDay { return KcalGoal(goalKcal: goalKcal, basis: .subtractDeficit(.deficit(kcalPerDay: kcal))) }
            return nil
        default: return nil
        }
    }

    enum CodingKeys: String, CodingKey { case goalKcal, basis, deficitKcalPerDay, weeklyLossKg, targetKcal }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(goalKcal, forKey: .goalKcal)
        try c.encode(basis, forKey: .basis)
        try c.encodeOrNull(deficitKcalPerDay, .deficitKcalPerDay)
        try c.encodeOrNull(weeklyLossKg, .weeklyLossKg)
        try c.encodeOrNull(targetKcal, .targetKcal)
    }
}

// MARK: - Limits

public nonisolated struct TargetLimits: Codable, Equatable, Sendable {
    /// nil = no cap. Never clamped, never changed by the app.
    public var hrCapBpm: Int?
    /// yyyy-MM-dd the user last answered / confirmed the cap question (8-week re-check).
    public var hrCapConfirmedOn: String?
    /// The user's zones; nil = not entered. Invalid zones decode as nil.
    public var zones: HrZones?
    public var avoidZone5: Bool

    public init(hrCapBpm: Int? = nil, hrCapConfirmedOn: String? = nil, zones: HrZones? = nil, avoidZone5: Bool = false) {
        self.hrCapBpm = hrCapBpm; self.hrCapConfirmedOn = hrCapConfirmedOn; self.zones = zones; self.avoidZone5 = avoidZone5
    }

    enum CodingKeys: String, CodingKey { case hrCapBpm, hrCapConfirmedOn, zones, avoidZone5 }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hrCapBpm = c.lenient(Int.self, .hrCapBpm)
        hrCapConfirmedOn = c.lenient(String.self, .hrCapConfirmedOn)
        zones = c.lenient(HrZones.self, .zones).flatMap { $0.isValid ? $0 : nil }
        avoidZone5 = c.lenient(Bool.self, .avoidZone5) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeOrNull(hrCapBpm, .hrCapBpm)
        try c.encodeOrNull(hrCapConfirmedOn, .hrCapConfirmedOn)
        try c.encodeOrNull(zones, .zones)
        try c.encode(avoidZone5, forKey: .avoidZone5)
    }
}

// MARK: - Rules

/// Stored rule values. nil = not changed = the recommended value applies.
public nonisolated struct TargetRules: Codable, Equatable, Sendable {
    public private(set) var values: [RuleMetric: Double]

    public init(_ values: [RuleMetric: Double] = [:]) { self.values = values }

    public subscript(rule: RuleMetric) -> Double? {
        get { values[rule] }
        set { values[rule] = newValue }
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var v: [RuleMetric: Double] = [:]
        for r in RuleMetric.allCases { if let x = c.lenient(Double.self, Key(r.rawValue)) { v[r] = x } }
        values = v
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for r in RuleMetric.allCases {
            let k = Key(r.rawValue)
            switch values[r] {
            case nil: try c.encodeNil(forKey: k)
            case let x? where r.isInteger: try c.encode(Int(x.rounded()), forKey: k)
            case let x?: try c.encode(x, forKey: k)
            }
        }
    }
}

// MARK: - Document

public nonisolated struct TargetsDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// The Outbox kind of the one mirror body (`PUT /api/v1/planning/targets`).
    public static let outboxKind = "targets"
    public static let empty = TargetsDocument()

    public var version: Int
    public var goals: TargetGoals
    public var limits: TargetLimits
    public var rules: TargetRules

    public init(goals: TargetGoals = TargetGoals(), limits: TargetLimits = TargetLimits(), rules: TargetRules = TargetRules()) {
        self.version = Self.currentVersion; self.goals = goals; self.limits = limits; self.rules = rules
    }

    enum CodingKeys: String, CodingKey { case version, goals, limits, rules }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.lenient(Int.self, .version) ?? Self.currentVersion
        goals = c.lenient(TargetGoals.self, .goals) ?? TargetGoals()
        limits = c.lenient(TargetLimits.self, .limits) ?? TargetLimits()
        rules = c.lenient(TargetRules.self, .rules) ?? TargetRules()
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(goals, forKey: .goals)
        try c.encode(limits, forKey: .limits)
        try c.encode(rules, forKey: .rules)
    }

    /// The hub body: this document with snake_case keys (for `HubClient.send`'s plain encoder).
    public func wireBody() throws -> JSONValue { try JSONValue.snakeCased(self) }

    // MARK: Accessors (spec §3 invariant b: every consumer reads through these)

    /// The one goal number per metric; nil = no goal. kcal = the target (goal − deficit).
    public func goal(_ metric: GoalMetric) -> Double? {
        switch metric {
        case .weight: goals.weight?.targetKg
        case .kcal: goals.kcal?.targetKcal
        case .protein: goals.proteinG
        case .carbs: goals.carbsG
        case .fat: goals.fatG
        case .steps: goals.stepsDaily.map(Double.init)
        case .sleep: goals.sleepH
        }
    }

    /// nil = no limit. The Zone 5 floor only counts when the user chose to avoid Zone 5.
    public func limit(_ metric: LimitMetric) -> Double? {
        switch metric {
        case .hrCap: limits.hrCapBpm.map(Double.init)
        case .zone5Floor: workoutLimits.zone5FloorBpm.map(Double.init)
        }
    }

    /// The rule the call uses: the user's value, else the recommended one.
    public func rule(_ metric: RuleMetric) -> Double { rules[metric] ?? metric.recommended }

    /// "recommended" until changed (a stored value equal to the recommendation is still recommended).
    public func isRecommended(_ metric: RuleMetric) -> Bool {
        rules[metric].map { $0 == metric.recommended } ?? true
    }

    /// What the Watch builder must respect.
    public var workoutLimits: WorkoutHrLimits {
        WorkoutHrLimits(capBpm: limits.hrCapBpm, zone5FloorBpm: limits.avoidZone5 ? limits.zones?.zone5FloorBpm : nil)
    }

    /// The nutrition goals as `MacroGoals` (the B-73 shape every nutrition surface reads).
    public var macroGoals: MacroGoals {
        get { MacroGoals(kcal: goals.kcal, proteinG: goals.proteinG, carbsG: goals.carbsG, fatG: goals.fatG) }
        set { goals.kcal = newValue.kcal; goals.proteinG = newValue.proteinG; goals.carbsG = newValue.carbsG; goals.fatG = newValue.fatG }
    }
}

// MARK: - Coding helpers

extension KeyedDecodingContainer {
    /// Field-by-field tolerant: missing, null or unreadable = nil (never invented).
    nonisolated func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

extension KeyedEncodingContainer {
    /// Unset is written as an explicit JSON null so the hub sees every key.
    nonisolated mutating func encodeOrNull<T: Encodable>(_ value: T?, _ key: Key) throws {
        if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
    }
}
