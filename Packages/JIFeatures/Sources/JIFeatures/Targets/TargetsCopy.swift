import Foundation
import JICore
import JIDesign

// W-TGT L3 (P-targets, spec HT docs/superpowers/specs/2026-09-28-targets-alignment-design.md §4,
// mockups docs/research/2026-09-28-targets/01–05) — the PURE half of Settings › Targets: the rows
// the screen draws, the Settings row summary, the editor sheet's draft and its write into the ONE
// document. Every number is the user's (Goals, Limits) or the rule's recommendation (Rules);
// nothing here invents one: a missing goal is "—" + "no goal", never a default.
//
// Copy rules (spec §4): "goal" for Goals, "cap"/"zones" for Limits, "rule" for Rules, "your
// normal" for computed; never "threshold" / "override". Every rule row says "recommended" until
// changed and "yours" after.

/// What one Targets row (and the editor sheet it opens) is about.
public nonisolated enum TargetSubject: Hashable, Sendable, Identifiable {
    case goal(GoalMetric)
    case rule(RuleMetric)
    /// The four load rules edited together: band low–high, over (reduce), under (maintain).
    case loadBand
    case hrCap
    case zones
    case avoidZone5

    public var id: String {
        switch self {
        case .goal(let m): "goal.\(m.rawValue)"
        case .rule(let r): "rule.\(r.rawValue)"
        case .loadBand: "rule.loadBand"
        case .hrCap: "limit.hrCap"
        case .zones: "limit.zones"
        case .avoidZone5: "limit.avoidZone5"
        }
    }

    /// The rules this subject's editor shows (a goal's paired rule sits under the goal, spec D1).
    public var rules: [RuleMetric] {
        switch self {
        case .goal(.kcal): [.weekKcalFloor]
        case .goal(.protein): [.weekProteinFloor]
        case .goal: []
        case .rule(let r): [r]
        case .loadBand: [.loadBandLow, .loadBandHigh, .loadOver, .loadUnder]
        case .hrCap, .zones, .avoidZone5: []
        }
    }

    public var title: String {
        switch self {
        case .goal(let m): targetsGoalTitle(m)
        case .rule(let r): targetsRuleTitle(r)
        case .loadBand: "Load band"
        case .hrCap: "HR cap"
        case .zones: "Zones"
        case .avoidZone5: "Avoid Zone 5"
        }
    }

    /// "Read by: …" — the one line under the editor that names the consequence (mock 02).
    public var readBy: String {
        switch self {
        case .goal(.kcal): "Today fuel · Nutrition ring · Weekly plan · morning call · KPI square"
        case .goal(.protein), .goal(.carbs), .goal(.fat): "Today fuel · Nutrition ring · KPI square"
        case .goal(.weight): "Goals · Trends · KPI square"
        case .goal(.steps): "Goals · KPI square · morning call"
        case .goal(.sleep): "Decide · Recovery · Today tonight"
        case .rule(.weekKcalFloor), .rule(.weekProteinFloor), .rule(.weekSleepScoreFloor), .loadBand,
             .rule(.loadOver), .rule(.loadUnder), .rule(.loadBandLow), .rule(.loadBandHigh):
            "Training recommendation · morning call"
        case .rule: "morning call"
        case .hrCap, .zones, .avoidZone5: "Training · Watch workouts · morning call"
        }
    }
}

// MARK: - Titles, units, formatting

public nonisolated func targetsGoalTitle(_ m: GoalMetric) -> String {
    switch m {
    case .weight: "Weight"
    case .kcal: "Calories"
    case .protein: "Protein"
    case .carbs: "Carbs"
    case .fat: "Fat"
    case .steps: "Daily steps"
    case .sleep: "Sleep"
    }
}

public nonisolated func targetsGoalUnit(_ m: GoalMetric) -> String {
    switch m {
    case .weight: "kg"
    case .kcal: "kcal"
    case .protein, .carbs, .fat: "g"
    case .steps: "steps"
    case .sleep: "h"
    }
}

nonisolated func targetsGoalDecimals(_ m: GoalMetric) -> Int {
    switch m {
    case .weight, .sleep: 1
    case .kcal, .protein, .carbs, .fat, .steps: 0
    }
}

public nonisolated func targetsRuleTitle(_ r: RuleMetric) -> String {
    switch r {
    case .hrvLowNights: "How cautious"
    case .respDeltaAmber: "Breathing rate"
    case .carbThreeDayFloor: "3-day carb floor"
    case .intervalMinSleep: "Garmin nights · interval floor"
    case .loadOver: "Load over"
    case .loadUnder: "Load under"
    case .loadBandLow: "Band low"
    case .loadBandHigh: "Band high"
    case .weekKcalFloor: "Week under fuel"
    case .weekProteinFloor: "Week under protein"
    case .weekSleepScoreFloor: "Week of poor sleep"
    }
}

/// One plain line under each rule (what the number does).
public nonisolated func targetsRuleExplanation(_ r: RuleMetric) -> String {
    switch r {
    case .hrvLowNights: "low HRV nights in a row before the call turns Modified"
    case .respDeltaAmber: "amber this far above your usual"
    case .carbThreeDayFloor: "hard sessions turn Modified below it"
    case .intervalMinSleep: "below this, intervals turn Modified"
    case .loadOver: "above this, the training call is Reduce"
    case .loadUnder: "below this, the training call is Maintain"
    case .loadBandLow, .loadBandHigh: "progress zone"
    case .weekKcalFloor: "7-day average kcal below"
    case .weekProteinFloor: "7-day average below"
    case .weekSleepScoreFloor: "7-day sleep score below"
    }
}

nonisolated func targetsRuleDecimals(_ r: RuleMetric) -> Int {
    switch r {
    case .hrvLowNights, .carbThreeDayFloor, .weekKcalFloor, .weekProteinFloor, .weekSleepScoreFloor: 0
    case .respDeltaAmber, .intervalMinSleep: 1
    case .loadOver, .loadUnder, .loadBandLow, .loadBandHigh: 2
    }
}

/// Stepper increment per rule / goal (the − / + buttons; typing is always allowed).
public nonisolated func targetsRuleStep(_ r: RuleMetric) -> Double {
    switch r {
    case .hrvLowNights: 1
    case .respDeltaAmber, .intervalMinSleep: 0.5
    case .carbThreeDayFloor: 10
    case .loadOver, .loadUnder, .loadBandLow, .loadBandHigh: 0.05
    case .weekKcalFloor: 50
    case .weekProteinFloor: 5
    case .weekSleepScoreFloor: 1
    }
}

public nonisolated func targetsGoalStep(_ m: GoalMetric) -> Double {
    switch m {
    case .weight: 0.5
    case .kcal: 50
    case .protein, .carbs, .fat: 5
    case .steps: 500
    case .sleep: 0.25
    }
}

/// "1,617" / "7,000" / "75.0" — grouped, fixed decimals, en-GB (the app's number style).
public nonisolated func targetsNumber(_ v: Double, _ decimals: Int) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.numberStyle = .decimal
    f.usesGroupingSeparator = true
    f.minimumFractionDigits = decimals
    f.maximumFractionDigits = decimals
    return f.string(from: NSNumber(value: v)) ?? jiNumber(v, decimals)
}

/// The value a rule shows ("2 nights", "+2.0 /min", "1,600 kcal", "0.80–1.30", "55").
public nonisolated func targetsRuleValueText(_ r: RuleMetric, _ v: Double) -> String {
    let n = targetsNumber(v, targetsRuleDecimals(r))
    switch r {
    case .hrvLowNights: return "\(n) \(Int(v.rounded()) == 1 ? "night" : "nights")"
    case .respDeltaAmber: return "+\(n) /min"
    case .carbThreeDayFloor, .weekProteinFloor: return "\(n) g"
    case .intervalMinSleep: return "\(n) h"
    case .weekKcalFloor: return "\(n) kcal"
    case .loadOver, .loadUnder, .loadBandLow, .loadBandHigh, .weekSleepScoreFloor: return n
    }
}

/// A goal's value on its row: "75.0 kg", "1,617 kcal", "— g" (no goal).
public nonisolated func targetsGoalValueText(_ m: GoalMetric, _ v: Double?) -> String {
    guard let v, v.isFinite else { return "— \(targetsGoalUnit(m))" }
    return "\(targetsNumber(v, targetsGoalDecimals(m))) \(targetsGoalUnit(m))"
}

/// "goal 7 h", "goal 1,617" — the short caption a square / KPI detail / Decide uses.
public nonisolated func targetsGoalCaption(_ m: GoalMetric, _ v: Double) -> String {
    switch m {
    case .sleep: "goal \(jiNumber(v, v.rounded() == v ? 0 : 1)) h"
    case .weight: "goal \(targetsNumber(v, 1))"
    case .protein, .carbs, .fat: "goal \(targetsNumber(v, 0)) g"
    case .kcal, .steps: "goal \(targetsNumber(v, 0))"
    }
}

/// Settings › Targets row subtitle (mock 04): "7 goals · cap 175 · rules recommended".
public nonisolated func targetsSettingsSummary(_ doc: TargetsDocument) -> String {
    let goals = GoalMetric.allCases.filter { doc.goal($0) != nil }.count
    let goalText = goals == 0 ? "no goals" : "\(goals) \(goals == 1 ? "goal" : "goals")"
    let cap = doc.limits.hrCapBpm.map { "cap \($0)" } ?? "no cap"
    let yours = RuleMetric.allCases.filter { !doc.isRecommended($0) }.count
    let rules = yours == 0 ? "rules recommended" : "\(yours) \(yours == 1 ? "rule" : "rules") yours"
    return [goalText, cap, rules].joined(separator: " · ")
}

// MARK: - Rows

public nonisolated struct TargetsRow: Equatable, Sendable, Identifiable {
    public let subject: TargetSubject
    public let title: String
    public let subtitle: String?
    public let value: String
    public let systemImage: String
    public let tint: JIColorRole
    /// Rules only: "recommended" until changed, "yours" after. nil on goals / limits.
    public let ruleTag: String?
    public var id: String { subject.id }
}

public nonisolated enum TargetsRows {
    public static let goalsHeader = "Goals · what you aim for"
    public static let limitsHeader = "Limits · what you never exceed"
    public static let rulesHeader = "Rules · how the call is made"
    public static let subtitle = "Your numbers. The app never fills one in."
    public static let strengthFooter = "Strength targets come from your logged sessions (next working weight) — nothing to type."
    public static let limitsFooter = "Optional. No cap = none. Change a limit with your clinician, not with a good week."
    public static let rulesIntro = "Overnight signals are compared with your own 28-day band. Rules below decide when a night outside it turns Full into Modified. Recommended values are set; a rule shows yours once you change it."
    public static let resetRules = "Reset rules to recommended"
    public static let resetFooter = "Goals and limits are never reset by the app."
    public static let goalOrder: [GoalMetric] = [.weight, .kcal, .protein, .carbs, .fat, .steps, .sleep]

    public static func goals(_ doc: TargetsDocument) -> [TargetsRow] {
        goalOrder.map { m in
            TargetsRow(subject: .goal(m), title: targetsGoalTitle(m), subtitle: goalSubtitle(m, doc),
                       value: targetsGoalValueText(m, doc.goal(m)), systemImage: goalSymbol(m), tint: goalTint(m), ruleTag: nil)
        }
    }

    static func goalSubtitle(_ m: GoalMetric, _ doc: TargetsDocument) -> String? {
        guard doc.goal(m) != nil else { return "no goal" }
        switch m {
        case .weight: return doc.goals.weight?.targetDate.flatMap(targetsLongDate).map { "by \($0)" }
        case .kcal: return doc.goals.kcal.map(kcalBasisText)
        case .sleep: return "read by Decide and Recovery"
        case .protein, .carbs, .fat, .steps: return nil
        }
    }

    /// The kcal goal's basis in words: what was typed and what the target is made of.
    public static func kcalBasisText(_ k: KcalGoal) -> String {
        switch k.basis {
        case .includesDeficit: return "your tracker's goal already includes the deficit"
        case .subtractDeficit(.deficit(let kcal)):
            return "goal \(targetsNumber(k.goalKcal, 0)) − deficit \(targetsNumber(kcal, 0))"
        case .subtractDeficit(.weeklyLoss(let kg)):
            return "goal \(targetsNumber(k.goalKcal, 0)) − \(targetsNumber(kg, 2)) kg a week"
        }
    }

    public static func limits(_ doc: TargetsDocument, today: String) -> [TargetsRow] {
        let cap = doc.limits.hrCapBpm
        let capSubtitle: String = {
            guard cap != nil else { return "no cap" }
            guard let on = doc.limits.hrCapConfirmedOn, let shown = targetsShortDate(on) else { return "not confirmed yet" }
            return "confirmed \(shown) · re-check every \(GateSettings.recheckWeeks) wk"
        }()
        let zones = doc.limits.zones
        let zonesSubtitle = zones.map { "from \($0.anchor == .maxHr ? "max HR" : "LTHR") \($0.anchorBpm) · Z5 from \($0.zone5FloorBpm.map(String.init) ?? "—")" }
            ?? "not entered"
        _ = today
        return [
            TargetsRow(subject: .hrCap, title: "HR cap", subtitle: capSubtitle, value: cap.map { "\($0) bpm" } ?? "No cap",
                       systemImage: "heart.circle", tint: .danger, ruleTag: nil),
            TargetsRow(subject: .zones, title: "Zones", subtitle: zonesSubtitle, value: zones == nil ? "—" : "5 floors",
                       systemImage: "waveform.path.ecg", tint: .info, ruleTag: nil),
            TargetsRow(subject: .avoidZone5, title: "Avoid Zone 5",
                       subtitle: zones == nil ? "needs your zones first" : "no session or Watch step targets Z5",
                       value: doc.limits.avoidZone5 ? "On" : "Off", systemImage: "hand.raised", tint: .reduced, ruleTag: nil),
        ]
    }

    public static func rules(_ doc: TargetsDocument) -> [TargetsRow] {
        func tag(_ rs: [RuleMetric]) -> String { rs.allSatisfy(doc.isRecommended) ? "recommended" : "yours" }
        func row(_ r: RuleMetric, _ symbol: String, subtitle: String? = nil) -> TargetsRow {
            TargetsRow(subject: .rule(r), title: targetsRuleTitle(r), subtitle: subtitle ?? targetsRuleExplanation(r),
                       value: targetsRuleValueText(r, doc.rule(r)), systemImage: symbol, tint: .info, ruleTag: tag([r]))
        }
        let nights = doc.rule(.hrvLowNights)
        let preset = GatePreset(hrvLowNights: nights)
        let band = "\(targetsNumber(doc.rule(.loadBandLow), 2))–\(targetsNumber(doc.rule(.loadBandHigh), 2))"
        return [
            row(.hrvLowNights, "gauge.with.dots.needle.50percent",
                subtitle: "\(preset.title) · modified after \(targetsNumber(nights, 0)) low HRV \(Int(nights.rounded()) == 1 ? "night" : "nights") in a row"),
            row(.respDeltaAmber, "lungs"),
            row(.carbThreeDayFloor, "fork.knife"),
            row(.intervalMinSleep, "bed.double"),
            TargetsRow(subject: .loadBand, title: "Load band", subtitle: "progress zone · over = reduce, under = maintain",
                       value: band, systemImage: "chart.bar", tint: .info, ruleTag: tag(TargetSubject.loadBand.rules)),
            row(.weekKcalFloor, "flame"),
            row(.weekProteinFloor, "fish"),
            row(.weekSleepScoreFloor, "moon.zzz"),
        ]
    }

    static func goalSymbol(_ m: GoalMetric) -> String {
        switch m {
        case .weight: "scalemass"
        case .kcal: "flame"
        case .protein: "fish"
        case .carbs: "leaf"
        case .fat: "drop"
        case .steps: "figure.walk"
        case .sleep: "bed.double"
        }
    }

    static func goalTint(_ m: GoalMetric) -> JIColorRole {
        switch m {
        case .weight: .info
        case .kcal: .kcal
        case .protein: .protein
        case .carbs: .carbs
        case .fat: .fat
        case .steps: .info
        case .sleep: .sleep
        }
    }
}

nonisolated private func isoDay(_ iso: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
    return f.date(from: String(iso.prefix(10)))
}

/// "31 Oct 2026" from "2026-10-31"; nil when unreadable.
nonisolated func targetsLongDate(_ iso: String) -> String? {
    guard let d = isoDay(iso) else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "d MMM yyyy"
    return f.string(from: d)
}

/// "24 Sep" from "2026-09-24".
nonisolated func targetsShortDate(_ iso: String) -> String? {
    guard let d = isoDay(iso) else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "d MMM"
    return f.string(from: d)
}

// MARK: - Parsing

/// A typed number. "" = none (nil); "1,617" = 1617 (a comma before exactly three digits groups);
/// "7,5" = 7.5. Unreadable text is an error — the sheet never guesses. No bounds (spec §4).
public nonisolated enum TargetsParsed: Equatable, Sendable {
    case none
    case value(Double)
    case invalid
}

public nonisolated func targetsParse(_ text: String) -> TargetsParsed {
    var s = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
    s = s.replacingOccurrences(of: "\u{2212}", with: "-")
    guard !s.isEmpty else { return .none }
    if s.contains(",") {
        let parts = s.split(separator: ",", omittingEmptySubsequences: false)
        let grouping = parts.count > 1 && parts.dropFirst().allSatisfy { $0.count == 3 || ($0.count > 3 && $0.contains(".") && $0.prefix { $0 != "." }.count == 3) }
        s = grouping ? s.replacingOccurrences(of: ",", with: "") : s.replacingOccurrences(of: ",", with: ".")
    }
    guard let v = Double(s), v.isFinite else { return .invalid }
    return .value(v)
}

/// The text a field starts with for a stored value ("" when none).
public nonisolated func targetsFieldText(_ v: Double?, decimals: Int) -> String {
    guard let v else { return "" }
    // Whole numbers without a trailing ".0" in a field; no grouping (it is typed over).
    if v.rounded() == v { return jiNumber(v, 0) }
    return jiNumber(v, decimals)
}

// MARK: - Editor draft

/// What the editor sheet holds while the user types. `applied(to:)` writes it into the document
/// (one number per metric and kind); a blank goal is "no goal", a blank rule is "recommended".
public nonisolated struct TargetEditDraft: Equatable, Sendable {
    public enum Failure: Error, Equatable, Sendable { case unreadable(String) }

    public let subject: TargetSubject
    /// The goal number (kcal: the tracker's daily goal before any deficit).
    public var goalText: String
    /// kcal only: the wanted deficit (kcal/day, or kg/week when `deficitIsWeeklyLoss`).
    public var deficitText: String
    public var deficitIsWeeklyLoss: Bool
    /// kcal only: the tracker's goal already includes the deficit (JI never subtracts twice).
    public var trackerIncludesDeficit: Bool
    /// weight only: yyyy-MM-dd or nil.
    public var weightDate: String?
    public var ruleTexts: [RuleMetric: String]

    public init(subject: TargetSubject, document doc: TargetsDocument) {
        self.subject = subject
        goalText = ""; deficitText = ""; deficitIsWeeklyLoss = false; trackerIncludesDeficit = false; weightDate = nil
        var rules: [RuleMetric: String] = [:]
        for r in subject.rules { rules[r] = targetsFieldText(doc.rule(r), decimals: targetsRuleDecimals(r)) }
        ruleTexts = rules
        guard case .goal(let m) = subject else { return }
        switch m {
        case .kcal:
            if let k = doc.goals.kcal {
                goalText = targetsFieldText(k.goalKcal, decimals: 0)
                switch k.basis {
                case .includesDeficit: trackerIncludesDeficit = true
                case .subtractDeficit(.deficit(let kcal)): deficitText = targetsFieldText(kcal, decimals: 0)
                case .subtractDeficit(.weeklyLoss(let kg)): deficitText = targetsFieldText(kg, decimals: 2); deficitIsWeeklyLoss = true
                }
            }
        case .weight:
            goalText = targetsFieldText(doc.goals.weight?.targetKg, decimals: 1)
            weightDate = doc.goals.weight?.targetDate
        default:
            goalText = targetsFieldText(doc.goal(m), decimals: targetsGoalDecimals(m))
        }
    }

    /// The kcal target the typed goal and deficit make ("Target 1,617 kcal"); nil without a goal.
    public var kcalTargetPreview: Double? {
        guard case .value(let goal) = targetsParse(goalText) else { return nil }
        guard let k = kcalGoal(goal: goal) else { return goal }
        return k.targetKcal
    }

    private func kcalGoal(goal: Double) -> KcalGoal? {
        if trackerIncludesDeficit { return KcalGoal(goalKcal: goal, basis: .includesDeficit) }
        switch targetsParse(deficitText) {
        case .value(let d):
            return KcalGoal(goalKcal: goal, basis: .subtractDeficit(deficitIsWeeklyLoss ? .weeklyLoss(kgPerWeek: d) : .deficit(kcalPerDay: d)))
        case .none, .invalid:
            // No deficit typed: the goal is the target (the tracker's goal is what the user eats to).
            return KcalGoal(goalKcal: goal, basis: .includesDeficit)
        }
    }

    public func applied(to document: TargetsDocument) -> Result<TargetsDocument, Failure> {
        var doc = document
        for (rule, text) in ruleTexts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            switch targetsParse(text) {
            case .none: doc.rules[rule] = nil
            case .value(let v):
                let x = rule.isInteger ? v.rounded() : v
                // Saving the recommendation unchanged keeps the rule "recommended" (nil), no value change.
                doc.rules[rule] = (x == rule.recommended && document.rules[rule] == nil) ? nil : x
            case .invalid: return .failure(.unreadable(targetsRuleTitle(rule)))
            }
        }
        guard case .goal(let m) = subject else { return .success(doc) }
        let parsed = targetsParse(goalText)
        if parsed == .invalid { return .failure(.unreadable(targetsGoalTitle(m))) }
        let value: Double? = if case .value(let v) = parsed { v } else { nil }
        switch m {
        case .kcal:
            if let value {
                if !trackerIncludesDeficit, targetsParse(deficitText) == .invalid { return .failure(.unreadable("Deficit")) }
                doc.goals.kcal = kcalGoal(goal: value)
            } else {
                doc.goals.kcal = nil
            }
        case .protein: doc.goals.proteinG = value
        case .carbs: doc.goals.carbsG = value
        case .fat: doc.goals.fatG = value
        case .steps: doc.goals.stepsDaily = value.map { Int($0.rounded()) }
        case .sleep: doc.goals.sleepH = value
        case .weight:
            if let value {
                var w = doc.goals.weight ?? WeightTarget()
                w.targetKg = value
                w.targetDate = weightDate
                doc.goals.weight = w
            } else {
                // No target = no weight goal; the start weight alone is not a goal.
                doc.goals.weight = nil
            }
        }
        return .success(doc)
    }

    /// − / + on a field: steps from the typed value (or the recommendation / nothing).
    public static func stepped(_ text: String, by delta: Double, decimals: Int, from fallback: Double?) -> String {
        let base: Double? = if case .value(let v) = targetsParse(text) { v } else { fallback }
        guard let base else { return text }
        let next = ((base + delta) * 1000).rounded() / 1000
        return jiNumber(next, decimals)
    }
}

/// The "Your normal" block (mock 02/03): computed, never stored; nil when the caller has none.
public nonisolated struct TargetNormalInfo: Equatable, Sendable {
    public let lastSevenText: String?
    public let normalText: String?
    public init(lastSevenText: String?, normalText: String?) { self.lastSevenText = lastSevenText; self.normalText = normalText }
}

/// The subject a KPI's Targets card edits (nil = the KPI has neither goal nor rule).
public nonisolated func targetsSubject(for metric: KpiMetricId) -> TargetSubject? {
    switch metric {
    case .kcal: .goal(.kcal)
    case .protein: .goal(.protein)
    case .carbs: .goal(.carbs)
    case .fat: .goal(.fat)
    case .steps: .goal(.steps)
    case .weight: .goal(.weight)
    case .sleep: .goal(.sleep)
    case .acwr: .loadBand
    case .hrv, .rhr, .bodyBattery, .readiness: nil
    }
}

/// KPI detail's Targets card lines (mock 03): Goal · Rule · Normal, each a sentence or nil.
public nonisolated struct KpiTargetsCardLines: Equatable, Sendable {
    public let goal: String?
    public let rule: String?
    public let ruleRecommended: Bool
}

public nonisolated func kpiTargetsCardLines(metric: KpiMetricId, document doc: TargetsDocument) -> KpiTargetsCardLines? {
    guard let subject = targetsSubject(for: metric) else { return nil }
    var goal: String?
    if case .goal(let m) = subject {
        if let v = doc.goal(m) {
            var line = targetsGoalValueText(m, v)
            if m == .kcal, let k = doc.goals.kcal, k.deficitKcalPerDay > 0 {
                line += " · deficit \(targetsNumber(k.deficitKcalPerDay, 0)) included"
            }
            goal = line
        } else {
            goal = "no goal"
        }
    }
    let rules = subject.rules
    let rule: String? = {
        switch subject {
        case .loadBand:
            return "band \(targetsNumber(doc.rule(.loadBandLow), 2))–\(targetsNumber(doc.rule(.loadBandHigh), 2)) · over \(targetsNumber(doc.rule(.loadOver), 2)) → Reduce · under \(targetsNumber(doc.rule(.loadUnder), 2)) → Maintain"
        default:
            guard let r = rules.first else { return nil }
            return "week under \(targetsRuleValueText(r, doc.rule(r))) → Reduce"
        }
    }()
    return KpiTargetsCardLines(goal: goal, rule: rule, ruleRecommended: rules.allSatisfy(doc.isRecommended))
}
