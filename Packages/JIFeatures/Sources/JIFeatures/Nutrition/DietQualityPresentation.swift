import Foundation
import JICore
import JICompute

/// B-99 p5 — the "Diet quality" card on Nutrition (mockup `docs/waves/mockups/bevel/BP-20.html`).
/// JI-owned formula ("JI reference", no Bevel parity claim). No red / penalty framing: the band
/// words are "Strong", "Mixed", "Room to grow"; an unscored day is "incomplete", never low.
///
/// Source order for the selected day:
/// 1. the hub's `diet_quality` (`/nutrition/daily`, B-99 p4) — YAZIO items incl. saturated fat
///    and the "based on N% of logged kcal" coverage;
/// 2. hub-less fallback: `JICompute.DietQuality` on-device over Apple Health day totals
///    (`HKDailyTotalsReader`: fibre + sugar + protein; Health holds no saturated fat for YAZIO —
///    card open question 2, conservative default) or, on an old hub without `diet_quality`, the
///    hub row's own grams.
public nonisolated enum DietQualitySource: Sendable, Equatable { case hub, appleHealth, onDevice }

public nonisolated struct DietQualityRow: Sendable, Equatable, Identifiable {
    /// Wire key: `fibre` | `sugar` | `sat_fat` | `protein`.
    public let key: String
    public let title: String
    public let detail: String
    /// 0-100 (rounded) or nil when n/a / withheld on an incomplete day.
    public let score: Int?
    /// "61", "n/a" (no data — never 0) or "—" (incomplete day, a partial-day ratio is withheld).
    public let scoreText: String
    public var id: String { key }
}

public nonisolated struct DietQualityPresentation: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case scored(Int)
        /// The gate's line, e.g. "Incomplete day · 2 of 3 meals".
        case incomplete(String)
        case noData
    }
    public let date: String
    public let state: State
    /// Scored: "Mixed · fibre is the short one". Incomplete: what the score needs. No data: a hint.
    public let headline: String
    public let rows: [DietQualityRow]
    /// Always shown: "Based on 73% of logged kcal · 3 meals logged" (or the source's equivalent).
    public let caption: String
    public let source: DietQualitySource?

    public var score: Int? { if case .scored(let s) = state { s } else { nil } }
}

public nonisolated let dietQualityTitle = "Diet quality"
public nonisolated let dietQualityGateCopy = "Score needs 3 meals and ≥ 60% of your kcal goal."

/// The sheet's four "how it is calculated" steps (mockup B).
public nonisolated let dietQualityMethodSteps: [(title: String, body: String)] = [
    ("Four contributors, 0–100 each",
     "Fibre against 14 g per 1,000 kcal eaten. Sugar and saturated fat against 10% of kcal, with a soft slope above it. Protein against your own goal."),
    ("Averaged over what we can see",
     "Equal weights, re-balanced over the contributors with data. A nutrient with no data shows \"n/a\", never 0."),
    ("Only on complete days",
     "Fewer than 3 meals or under 60% of your kcal goal = \"incomplete day\", no score. A missing day is never a low day."),
    ("Coverage is shown, not hidden",
     "The card states the share of the day's logged kcal whose food carries fibre, sugar and saturated-fat detail."),
]
public nonisolated let dietQualitySheetIntro =
    "One number for how the day's food was put together. It does not change your training call or your energy balance."
public nonisolated let dietQualitySheetFootnote =
    "Sugar is total sugar (fruit and dairy count). Thresholds: JI reference, not a Bevel or medical score. Not medical advice."

/// "Strong" ≥ 80, "Mixed" 60–79, "Room to grow" below — never a red or penalty word.
public nonisolated func dietQualityBand(_ score: Int) -> String {
    score >= 80 ? "Strong" : score >= 60 ? "Mixed" : "Room to grow"
}

private nonisolated func contributorName(_ key: String) -> String {
    switch key {
    case "fibre": "fibre"
    case "sugar": "sugar"
    case "sat_fat": "saturated fat"
    default: "protein"
    }
}

private nonisolated func g1(_ v: Double) -> String { String(format: "%.1f g", v) }
private nonisolated func g0(_ v: Double) -> String { "\(Int(v.rounded())) g" }
private nonisolated func pctOfKcal(_ grams: Double, kcalPerG: Double, kcal: Double?) -> String? {
    guard let kcal, kcal > 0 else { return nil }
    return "\(Int((grams * kcalPerG / kcal * 100).rounded()))% of kcal"
}

/// The day's inputs the rows describe (grams + kcal), whichever source scored it.
struct DietQualityAmounts: Sendable, Equatable {
    var kcal, fiberG, sugarG, satFatG, proteinG: Double?
}

nonisolated func dietQualityRows(contributors: [(key: String, score: Double?)], amounts a: DietQualityAmounts,
                                 proteinGoal: Double?, incomplete: Bool, source: DietQualitySource) -> [DietQualityRow] {
    let order = ["fibre", "sugar", "sat_fat", "protein"]
    let byKey = Dictionary(contributors.map { ($0.key, $0.score) }, uniquingKeysWith: { a, _ in a })
    return order.map { key in
        let score = byKey[key] ?? nil
        let soFar = incomplete ? " so far" : ""
        let detail: String
        let title: String
        switch key {
        case "fibre":
            title = "Fibre"
            if let f = a.fiberG {
                let aim = a.kcal.map { DietQuality.fibreGPer1000Kcal * $0 / 1000 }
                detail = g1(f) + soFar + (incomplete ? "" : aim.map { " · aim \(g0($0)) (14 g per 1,000 kcal)" } ?? "")
            } else { detail = "Not in the logged food" }
        case "sugar":
            title = "Sugar"
            if let s = a.sugarG {
                detail = ([g0(s) + soFar] + (incomplete ? [] : [pctOfKcal(s, kcalPerG: 4, kcal: a.kcal), "aim ≤ 10%"].compactMap { $0 }))
                    .joined(separator: " · ")
            } else { detail = "Not in the logged food" }
        case "sat_fat":
            title = "Saturated fat"
            if let s = a.satFatG {
                detail = ([g0(s) + soFar] + (incomplete ? [] : [pctOfKcal(s, kcalPerG: 9, kcal: a.kcal), "aim ≤ 10%"].compactMap { $0 }))
                    .joined(separator: " · ")
            } else { detail = source == .appleHealth ? "Not in Apple Health" : "Not in the logged food" }
        default:
            title = "Protein"
            if let p = a.proteinG {
                detail = g0(p) + (proteinGoal.map { " · goal \(g0($0))" } ?? " · set a protein goal")
            } else { detail = "Not in the logged food" }
        }
        // A partial day's ratio (fibre per kcal, % of kcal) is withheld; protein vs goal is not a ratio.
        let withheld = incomplete && key != "protein"
        let rounded = score.map { Int($0.rounded()) }
        let text = withheld ? "—" : (rounded.map(String.init) ?? "n/a")
        return DietQualityRow(key: key, title: title, detail: detail, score: withheld ? nil : rounded, scoreText: text)
    }
}

/// The selected day's card. `hubRow` = the hub's `/nutrition/daily` row for the day (its
/// `dietQuality` wins); `health` = Apple Health's totals for the day (hub-less fallback).
public nonisolated func dietQualityPresentation(date: String, hubRow: NutritionDailyRow?, health: HealthDailyTotals?,
                                                proteinGoal: Double?, kcalGoal: Double?) -> DietQualityPresentation {
    let meals = hubRow?.mealsLogged
    if let row = hubRow, let dq = row.dietQuality {
        let amounts = DietQualityAmounts(kcal: row.kcalConsumed, fiberG: row.fiberG, sugarG: row.sugarG, satFatG: row.satFatG, proteinG: row.proteinG)
        let rows = dietQualityRows(contributors: dq.contributors.map { ($0.key, $0.score) }, amounts: amounts,
                                   proteinGoal: proteinGoal, incomplete: dq.incomplete, source: .hub)
        let coverage = dq.coveragePct ?? row.coveragePct.map { Int($0.rounded()) }
        return make(date: date, score: dq.incomplete ? nil : dq.score, reason: dq.reason, rows: rows, meals: meals,
                    caption: hubCaption(coverage: coverage, meals: meals), source: .hub)
    }
    // Hub-less fallback: Apple Health's day totals when Health has the day's food, else the hub
    // row's own grams (old hub without `diet_quality`).
    let source: DietQualitySource
    let amounts: DietQualityAmounts
    let coverage: Double?
    if let h = health, h.hasFood {
        source = .appleHealth
        amounts = DietQualityAmounts(kcal: h.dietaryKcal, fiberG: h.fiberG, sugarG: h.sugarG, satFatG: nil, proteinG: h.proteinG)
        coverage = nil
    } else if let row = hubRow, [row.kcalConsumed, row.proteinG, row.fiberG, row.sugarG].contains(where: { $0 != nil }) {
        source = .onDevice
        amounts = DietQualityAmounts(kcal: row.kcalConsumed, fiberG: row.fiberG, sugarG: row.sugarG, satFatG: row.satFatG, proteinG: row.proteinG)
        coverage = row.coveragePct
    } else {
        return DietQualityPresentation(date: date, state: .noData, headline: "Scores appear once a day is complete.",
                                       rows: [], caption: "No food logged for this day.", source: nil)
    }
    // Health holds no meal count: with no hub row for the day the meal gate cannot be read, so
    // only the kcal gate applies (decision recorded in the B-99 p5 lane return).
    let mealCount: Double? = meals.map(Double.init) ?? (source == .appleHealth ? DietQuality.minMeals : nil)
    let result = DietQuality.compute(DietQuality.Input(
        kcal: amounts.kcal, fiberG: amounts.fiberG, sugarG: amounts.sugarG, satFatG: amounts.satFatG,
        proteinG: amounts.proteinG, proteinGoalG: proteinGoal, kcalGoal: kcalGoal ?? hubRow?.kcalGoal,
        mealCount: mealCount, coveragePct: coverage))
    let rows = dietQualityRows(contributors: result.contributors.map { ($0.key.rawValue, $0.score) }, amounts: amounts,
                               proteinGoal: proteinGoal, incomplete: result.incomplete, source: source)
    let caption = source == .appleHealth
        ? "From Apple Health day totals · saturated fat and coverage are not in Health" + (meals.map { " · \(mealsText($0))" } ?? "")
        : hubCaption(coverage: result.coveragePct, meals: meals)
    return make(date: date, score: result.score, reason: result.reason?.rawValue, rows: rows, meals: meals,
                caption: caption, source: source)
}

private nonisolated func mealsText(_ n: Int) -> String { n == 1 ? "1 meal logged" : "\(n) meals logged" }

private nonisolated func hubCaption(coverage: Int?, meals: Int?) -> String {
    let base = coverage.map { "Based on \($0)% of logged kcal" } ?? "Coverage of logged kcal unknown"
    return base + (meals.map { " · \(mealsText($0))" } ?? "")
}

private nonisolated func make(date: String, score: Int?, reason: String?, rows: [DietQualityRow], meals: Int?,
                              caption: String, source: DietQualitySource) -> DietQualityPresentation {
    if let score, reason == nil {
        let scored = rows.filter { $0.score != nil }
        let short = scored.min { $0.score! < $1.score! }
        let headline = dietQualityBand(score) + (short.flatMap { $0.score! < 80 ? " · \(contributorName($0.key)) is the short one" : nil } ?? "")
        return DietQualityPresentation(date: date, state: .scored(score), headline: headline, rows: rows, caption: caption, source: source)
    }
    let line: String
    switch reason {
    case "few_meals": line = meals.map { "Incomplete day · \($0) of 3 meals" } ?? "Incomplete day · meal count unknown"
    case "low_kcal": line = "Incomplete day · under 60% of your kcal goal"
    case "no_contributors": line = "Incomplete day · no fibre, sugar or protein data"
    default: line = "Incomplete day"
    }
    return DietQualityPresentation(date: date, state: .incomplete(line), headline: dietQualityGateCopy, rows: rows, caption: caption, source: source)
}
