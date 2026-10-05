import Foundation
import Testing
@testable import JICompute

/// B-99 p3: `DietQuality` against `diet_quality.golden.json` (byte-copy of HealthTraining
/// `tests/fixtures/diet_quality/golden.json`; ground truth `app/nutrition/diet_quality.py`).

struct DietQualityGoldenCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["name", "input", "expected"]

    struct Input: Decodable, Sendable {
        static let keys: Set<String> = ["kcal", "fiber_g", "sugar_g", "sat_fat_g", "protein_g",
                                        "protein_goal_g", "kcal_goal", "meal_count", "coverage_pct"]
        let kcal, fiber_g, sugar_g, sat_fat_g, protein_g, protein_goal_g, kcal_goal, meal_count, coverage_pct: Double?
        let rawKeys: Set<String>

        init(from decoder: Decoder) throws {
            rawKeys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
            let c = try decoder.container(keyedBy: AnyKey.self)
            func d(_ k: String) throws -> Double? { try c.decodeIfPresent(Double.self, forKey: AnyKey(k)) }
            kcal = try d("kcal"); fiber_g = try d("fiber_g"); sugar_g = try d("sugar_g")
            sat_fat_g = try d("sat_fat_g"); protein_g = try d("protein_g"); protein_goal_g = try d("protein_goal_g")
            kcal_goal = try d("kcal_goal"); meal_count = try d("meal_count"); coverage_pct = try d("coverage_pct")
        }

        var value: DietQuality.Input {
            DietQuality.Input(kcal: kcal, fiberG: fiber_g, sugarG: sugar_g, satFatG: sat_fat_g, proteinG: protein_g,
                              proteinGoalG: protein_goal_g, kcalGoal: kcal_goal, mealCount: meal_count,
                              coveragePct: coverage_pct)
        }
    }

    struct Contributor: Decodable, Sendable {
        let key: String
        let score: Double?
        let weight: Double?
    }

    struct Expected: Decodable, Sendable {
        let score: Int?
        let incomplete: Bool
        let reason: String?
        let contributors: [Contributor]
        let coverage_pct: Int?
        let formula_version: Int
    }

    let name: String
    let input: Input
    let expected: Expected
    var testDescription: String { name }
}

@Suite struct DietQualityTests {
    static let cases = GoldenLoader.require(DietQualityGoldenCase.self, file: "diet_quality.golden", group: "cases")

    @Test func goldenFileHasCoreScenarios() {
        let names = Set(Self.cases.map(\.name))
        #expect(Self.cases.count >= 10)
        for n in ["complete_all_at_target", "sat_fat_na_renormalised_not_zero", "gate_few_meals",
                  "gate_low_kcal_vs_goal", "no_contributors", "rounding_half_up"] {
            #expect(names.contains(n), "missing golden scenario \(n)")
        }
    }

    @Test func goldenInputsUseOnlyKnownKeys() {
        for c in Self.cases {
            #expect(c.input.rawKeys.isSubset(of: DietQualityGoldenCase.Input.keys), "\(c.name): unknown input key(s)")
        }
    }

    @Test(arguments: cases)
    func matchesPython(_ c: DietQualityGoldenCase) {
        let r = DietQuality.compute(c.input.value)
        let e = c.expected
        #expect(r.score == e.score)
        #expect(r.incomplete == e.incomplete)
        #expect(r.reason?.rawValue == e.reason)
        #expect(r.coveragePct == e.coverage_pct)
        #expect(r.formulaVersion == e.formula_version)
        #expect(r.contributors.map(\.key.rawValue) == e.contributors.map(\.key))
        for (g, x) in zip(r.contributors, e.contributors) {
            #expect(g.score == x.score, "\(g.key) score")
            switch (g.weight, x.weight) {
            case (nil, nil): break
            case let (gw?, xw?): #expect(abs(gw - xw) <= 1e-9, "\(g.key) weight")
            default: Issue.record("\(g.key): weight presence differs (\(String(describing: g.weight)) vs \(String(describing: x.weight)))")
            }
        }
    }

    @Test(arguments: [0.0, 1.0, 2.0])
    func fewMealsGatesTheScore(_ meals: Double) {
        let r = DietQuality.compute(.init(kcal: 2000, fiberG: 28, sugarG: 40, satFatG: 20, proteinG: 150,
                                          proteinGoalG: 150, kcalGoal: 2000, mealCount: meals))
        #expect(r.score == nil && r.incomplete && r.reason == .fewMeals)
    }

    @Test func missingMealCountIsIncomplete() {
        #expect(DietQuality.compute(.init(kcal: 2000, fiberG: 28)).reason == .fewMeals)
    }

    @Test func kcalGateBoundary() {
        let base = DietQuality.Input(kcal: 1200, fiberG: 20, kcalGoal: 2000, mealCount: 3)
        #expect(DietQuality.compute(base).score != nil)        // exactly 60 % passes
        var under = base; under.kcal = 1199.9
        #expect(DietQuality.compute(under).reason == .lowKcal)
    }

    @Test func naIsNotZeroAndWeightsRenormalise() {
        let r = DietQuality.compute(.init(kcal: 2000, fiberG: 28, sugarG: nil, satFatG: nil, proteinG: 75,
                                          proteinGoalG: 150, mealCount: 3))
        let present = r.contributors.compactMap(\.weight)
        #expect(present.count == 2)
        #expect(abs(present.reduce(0, +) - 1.0) < 1e-12)
        #expect(r.score == 75)
        #expect(r.contributors.first { $0.key == .sugar }?.score == nil)
    }

    @Test func zeroGramsIsDataNotNA() {
        let r = DietQuality.compute(.init(kcal: 2000, fiberG: 0, mealCount: 3))
        let fibre = r.contributors.first { $0.key == .fibre }
        #expect(fibre?.score == 0.0 && fibre?.weight == 1.0 && r.score == 0)
    }

    @Test func nanIsNA() {
        let r = DietQuality.compute(.init(kcal: 2000, fiberG: .nan, sugarG: 40, mealCount: 3, coveragePct: .nan))
        #expect(r.contributors.first { $0.key == .fibre }?.score == nil)
        #expect(r.coveragePct == nil && r.score == 100)
    }

    @Test func sugarSoftSlopeIsMonotonic() {
        let s = stride(from: 0.0, through: 200.0, by: 10.0).map {
            DietQuality.compute(.init(kcal: 2000, sugarG: $0, mealCount: 3)).contributors[1].score!
        }
        #expect(zip(s, s.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(s.first == 100.0 && s.last == 0.0)
    }

    @Test func coverageClampedAndRoundedHalfUp() {
        #expect(DietQuality.compute(.init(mealCount: 3, coveragePct: 140)).coveragePct == 100)
        #expect(DietQuality.compute(.init(mealCount: 3, coveragePct: -5)).coveragePct == 0)
        #expect(DietQuality.compute(.init(mealCount: 3, coveragePct: 2.5)).coveragePct == 3)
    }
}
