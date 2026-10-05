// W-DEAD-2 D2-9: gallery/preview support — compiled into Debug only, never the installed app.
#if DEBUG
import SwiftUI
import JICore
import JICompute
import JIDesign

/// §8.5 fixtures for the "Diet quality" registry entries (B-99 p5) — mockup BP-20's days:
/// Tue 22 Sep complete (1,620 / 1,617 kcal, 3 meals, 73 % coverage) and Mon 29 Sep incomplete
/// (2 meals, 1,384 kcal). The hub's `diet_quality` object is built with `JICompute.DietQuality`,
/// the same formula the hub runs (golden-file parity, B-99 p3).
nonisolated enum DietQualityFixtures {
    static let proteinGoal = 155.0
    static let kcalGoal = 1617.0

    static func hubRow(date: String, kcal: Double, fibre: Double?, sugar: Double?, satFat: Double?, protein: Double?,
                       meals: Int, coverage: Double?) -> NutritionDailyRow {
        let r = DietQuality.compute(DietQuality.Input(kcal: kcal, fiberG: fibre, sugarG: sugar, satFatG: satFat, proteinG: protein,
                                                      proteinGoalG: proteinGoal, kcalGoal: kcalGoal, mealCount: Double(meals),
                                                      coveragePct: coverage))
        let dto = DietQualityDTO(score: r.score, incomplete: r.incomplete, reason: r.reason?.rawValue,
                                 contributors: r.contributors.map { .init(key: $0.key.rawValue, score: $0.score, weight: $0.weight) },
                                 coveragePct: r.coveragePct, formulaVersion: r.formulaVersion)
        return NutritionDailyRow(date: date, kcalConsumed: kcal, kcalGoal: kcalGoal, proteinG: protein, mealsLogged: meals,
                                 fiberG: fibre, sugarG: sugar, satFatG: satFat, coveragePct: coverage, dietQuality: dto)
    }

    static let completeRow = hubRow(date: "2026-09-22", kcal: 1620, fibre: 13.9, sugar: 64, satFat: 20, protein: 127, meals: 3, coverage: 73)
    static let incompleteRow = hubRow(date: "2026-09-29", kcal: 1384, fibre: 3.0, sugar: 12, satFat: 9, protein: 152, meals: 2, coverage: 23)

    static var complete: DietQualityPresentation {
        dietQualityPresentation(date: completeRow.date, hubRow: completeRow, health: nil, proteinGoal: proteinGoal, kcalGoal: kcalGoal)
    }
    static var incomplete: DietQualityPresentation {
        dietQualityPresentation(date: incompleteRow.date, hubRow: incompleteRow, health: nil, proteinGoal: proteinGoal, kcalGoal: kcalGoal)
    }
    /// Hub-less: Apple Health day totals only (fibre + sugar + protein; no saturated fat).
    static var healthOnly: DietQualityPresentation {
        dietQualityPresentation(date: "2026-09-22", hubRow: nil,
                                health: HealthDailyTotals(date: "2026-09-22", dietaryKcal: 1620, proteinG: 127, fiberG: 13.9, sugarG: 64),
                                proteinGoal: proteinGoal, kcalGoal: kcalGoal)
    }
}

/// §8.5 registry entry "Diet quality": the card on a complete day (ring + value + coverage
/// caption), on an incomplete day (no score) and hub-less from Apple Health.
struct DietQualityNativePreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JISectionHeader("Diet quality · Tue 22 Sep")
                DietQualityCard(model: DietQualityFixtures.complete) {}
                JISectionHeader("Diet quality · Mon 29 Sep")
                DietQualityCard(model: DietQualityFixtures.incomplete) {}
                JISectionHeader("Diet quality · Apple Health only")
                DietQualityCard(model: DietQualityFixtures.healthOnly) {}
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            .readableColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JITheme.native.color(.bg))
    }
}

/// §8.5 registry entry "Diet quality method": the "How it is calculated" sheet on the complete day.
struct DietQualityMethodNativePreview: View {
    var body: some View { DietQualitySheet(model: DietQualityFixtures.complete) }
}
#endif
