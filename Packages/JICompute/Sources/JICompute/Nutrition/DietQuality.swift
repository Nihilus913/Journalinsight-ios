/// Diet quality score (B-99 p3) — Swift port of HealthTraining
/// `app/nutrition/diet_quality.py` (B-99 p2), formula version 1.
///
/// JI-owned formula ("JI reference"); no Bevel parity claim. Pure: one day's
/// totals in, a 0-100 score plus its contributors out. Ground truth is the
/// shared golden file `tests/fixtures/diet_quality/golden.json`, byte-copied to
/// `Tests/JIComputeTests/Resources/golden/diet_quality.golden.json`.
///
/// Contributors (each 0-100, equal base weight, renormalised over the ones with data):
/// - fibre:   >= 14 g per 1000 kcal eaten -> 100, linear below.
/// - sugar:   <= 10 % of kcal -> 100, soft linear slope to 0 at 25 % of kcal.
/// - satFat:  <= 10 % of kcal -> 100, linear slope to 0 at 20 % of kcal.
/// - protein: protein_g / protein_goal_g, capped at 100.
/// A contributor without data is n/a: left out of the weights, never scored 0.
///
/// Gate: < 3 meals, or < 60 % of the kcal goal eaten -> incomplete, no score.
/// `coveragePct` is passed through (clamped, rounded) for the
/// "based on N% of logged kcal" caption; the score does not use it.
///
/// Rounding mirrors the Python helper `_round_half_up` (`floor(x*m + 0.5) / m`)
/// with the same IEEE operations, so results are bit-identical.
public nonisolated enum DietQuality {
    public static let registryKey = "diet_quality"
    public static let formulaVersion = 1

    public static let fibreGPer1000Kcal = 14.0
    public static let sugarPctFull = 0.10
    public static let sugarPctZero = 0.25
    public static let satFatPctFull = 0.10
    public static let satFatPctZero = 0.20
    static let kcalPerGSugar = 4.0
    static let kcalPerGFat = 9.0

    public static let minMeals = 3.0
    public static let minGoalKcalShare = 0.60

    public enum ContributorKey: String, Sendable, Equatable, CaseIterable {
        case fibre
        case sugar
        case satFat = "sat_fat"
        case protein
    }

    public enum Reason: String, Sendable, Equatable {
        case fewMeals = "few_meals"
        case lowKcal = "low_kcal"
        case noContributors = "no_contributors"
        /// RG-44: nothing logged (0 meals, or no kcal with an unknown meal count) — the no-data state.
        case noData = "no_data"
    }

    /// RG-45: the food-composition contributors; protein alone is not a diet score.
    public static let foodContributors: [ContributorKey] = [.fibre, .sugar, .satFat]

    /// One day's totals. `nil` (or NaN) = unknown.
    public struct Input: Sendable, Equatable {
        public var kcal: Double?
        public var fiberG: Double?
        public var sugarG: Double?
        public var satFatG: Double?
        public var proteinG: Double?
        public var proteinGoalG: Double?
        public var kcalGoal: Double?
        public var mealCount: Double?
        public var coveragePct: Double?

        public init(kcal: Double? = nil, fiberG: Double? = nil, sugarG: Double? = nil, satFatG: Double? = nil,
                    proteinG: Double? = nil, proteinGoalG: Double? = nil, kcalGoal: Double? = nil,
                    mealCount: Double? = nil, coveragePct: Double? = nil) {
            self.kcal = kcal; self.fiberG = fiberG; self.sugarG = sugarG; self.satFatG = satFatG
            self.proteinG = proteinG; self.proteinGoalG = proteinGoalG; self.kcalGoal = kcalGoal
            self.mealCount = mealCount; self.coveragePct = coveragePct
        }
    }

    public struct Contributor: Sendable, Equatable {
        public let key: ContributorKey
        /// 0-100 rounded to one decimal, nil when n/a.
        public let score: Double?
        /// Renormalised weight (sums to 1 over present contributors), nil when n/a.
        public let weight: Double?
    }

    public struct Result: Sendable, Equatable {
        public let score: Int?
        public let incomplete: Bool
        public let reason: Reason?
        public let contributors: [Contributor]
        public let coveragePct: Int?
        public let formulaVersion: Int
    }

    static func num(_ v: Double?) -> Double? {
        guard let v, !v.isNaN else { return nil }
        return v
    }

    static func roundHalfUp(_ x: Double, digits: Int = 0) -> Double {
        var m = 1.0
        for _ in 0..<digits { m *= 10.0 }
        return (x * m + 0.5).rounded(.down) / m
    }

    static func clamp100(_ x: Double) -> Double { max(0.0, min(100.0, x)) }

    static func ceilingScore(_ pct: Double, full: Double, zero: Double) -> Double {
        if pct <= full { return 100.0 }
        return clamp100(100.0 * (zero - pct) / (zero - full))
    }

    static func contributorScores(kcal: Double, _ d: Input) -> [ContributorKey: Double] {
        var out: [ContributorKey: Double] = [:]
        if let fibre = num(d.fiberG), kcal > 0 {
            out[.fibre] = clamp100(100.0 * fibre / (fibreGPer1000Kcal * kcal / 1000.0))
        }
        if let sugar = num(d.sugarG), kcal > 0 {
            out[.sugar] = ceilingScore(sugar * kcalPerGSugar / kcal, full: sugarPctFull, zero: sugarPctZero)
        }
        if let sat = num(d.satFatG), kcal > 0 {
            out[.satFat] = ceilingScore(sat * kcalPerGFat / kcal, full: satFatPctFull, zero: satFatPctZero)
        }
        if let protein = num(d.proteinG), let goal = num(d.proteinGoalG), goal > 0 {
            out[.protein] = clamp100(100.0 * protein / goal)
        }
        return out
    }

    /// Score one day (mirrors `diet_quality(day)`).
    public static func compute(_ day: Input) -> Result {
        let kcal = num(day.kcal) ?? 0.0
        let meals = num(day.mealCount)
        let kcalGoal = num(day.kcalGoal)
        let coverage = num(day.coveragePct).map { Int(roundHalfUp(max(0.0, min(100.0, $0)))) }

        let scores = contributorScores(kcal: kcal, day)
        let present = ContributorKey.allCases.filter { scores[$0] != nil }
        let weight: Double? = present.isEmpty ? nil : 1.0 / Double(present.count)

        var reason: Reason?
        let rawKcal = num(day.kcal)
        if meals == 0 || (meals == nil && (rawKcal ?? 0) <= 0) {
            reason = .noData
        } else if meals == nil || meals! < minMeals {
            reason = .fewMeals
        } else if let kcalGoal, kcalGoal > 0, kcal < minGoalKcalShare * kcalGoal {
            reason = .lowKcal
        } else if !present.contains(where: { foodContributors.contains($0) }) {
            reason = .noContributors   // RG-45: none at all, or protein alone
        }

        let contributors = ContributorKey.allCases.map { key in
            Contributor(key: key,
                        score: scores[key].map { roundHalfUp($0, digits: 1) },
                        weight: scores[key] == nil ? nil : weight)
        }
        var score: Int?
        if reason == nil, let weight {
            // Same summation order as Python's `sum(...)` over CONTRIBUTORS order.
            var total = 0.0
            for key in present { total += scores[key]! * weight }
            score = Int(roundHalfUp(total))
        }
        return Result(score: score, incomplete: reason != nil, reason: reason,
                      contributors: contributors, coveragePct: coverage, formulaVersion: formulaVersion)
    }
}
