import SwiftUI
import JICore
import JIDesign

/// (W3a-L2, mirrors `mobile/src/components/nutrition/MacroSummaryCard.tsx`, trimmed to the fields
/// this port's `NutritionProviding` actually carries — protein/carbs/fat *goals* come from a
/// separate `planning/goals` endpoint the RN oracle reads that this screen's contract does not
/// list, so only the kcal goal renders here this wave). Rule 5: a missing value renders "—", never 0.
public struct MacroSummaryCard: View {
    let day: NutritionDayDetail?
    /// W4-L3 — when set, an edit-goals button (mirrors RN's `EditGoalButton`, L117) pushes
    /// `GoalsSetupView`. `nil` (the default) keeps every existing call site source-compatible and
    /// hides the button, same optional-model pattern as `VerdictHeroView.challengesModel`.
    let goalsSetupModel: GoalsSetupViewModel?
    @State private var showGoalsSetup = false
    @Environment(\.jiTheme) private var theme

    public init(day: NutritionDayDetail?, goalsSetupModel: GoalsSetupViewModel? = nil) {
        self.day = day
        self.goalsSetupModel = goalsSetupModel
    }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Macros today").jiFont(.caption).foregroundStyle(theme.color(.muted)).textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)
                    if let goalsSetupModel {
                        Spacer()
                        Button {
                            showGoalsSetup = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Edit nutrition goals")
                        .accessibilityIdentifier("macro-edit-goals")
                        // Attached locally, same rationale as VerdictHeroView.challengesModel's
                        // isPresented push — no need for the enclosing NavigationStack's own
                        // navigationDestination(for:), which lives outside this lane's file list.
                        .navigationDestination(isPresented: $showGoalsSetup) {
                            GoalsSetupView(model: goalsSetupModel)
                        }
                    }
                }
                if let day {
                    // §4b: Calories ring (green, 0 → goal) + the Fitness macro triple. Both are
                    // bounded-against-a-goal values; a ring renders ONLY when its goal is known,
                    // otherwise the numbers stand alone (rule 5 — never a ring against a guess).
                    AdaptiveHStack(spacing: 20) {
                        HStack(spacing: 16) {
                            if let kcal = day.total.kcal, let goal = day.total.kcalGoal, goal > 0 {
                                ScoreRing(value: kcal, max: goal, tint: theme.color(.go))
                                    .accessibilityLabel("Calories against goal")
                            }
                            kcalRow(day.total)
                        }
                        if let rings = macroGoalRings(day.total) {
                            HStack(spacing: 16) {
                                MacroRings(protein: rings.protein, carbs: rings.carbs, fat: rings.fat)
                                macroLegend(day.total)
                            }
                        }
                    }
                    Divider().overlay(theme.color(.hairlineNested))
                    macroRow(label: "Protein", value: day.total.proteinG, color: theme.color(.info))
                    macroRow(label: "Carbs", value: day.total.carbsG, color: theme.color(.reduced))
                    macroRow(label: "Fat", value: day.total.fatG, color: theme.color(.sleep))
                } else {
                    Text("No nutrition data yet for this day.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("macro-empty")
                }
            }
        }
    }

    /// The macro triple needs all three goals; the day payload carries only `kcalGoal`, so the
    /// rings come from the goals document when the screen was given one (`goalsSetupModel`).
    private func macroGoalRings(_ total: NutritionDayTotal) -> (protein: MacroRingValue, carbs: MacroRingValue, fat: MacroRingValue)? {
        guard let goal = goalsSetupModel?.goals?.nutrition,
              let pGoal = goal.proteinG, let cGoal = goal.carbsG, let fGoal = goal.fatG,
              pGoal > 0, cGoal > 0, fGoal > 0 else { return nil }
        return (MacroRingValue(value: total.proteinG ?? 0, goal: pGoal),
                MacroRingValue(value: total.carbsG ?? 0, goal: cGoal),
                MacroRingValue(value: total.fatG ?? 0, goal: fGoal))
    }

    private func macroLegend(_ total: NutritionDayTotal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Protein · Carbs · Fat").jiFont(.caption).foregroundStyle(theme.color(.muted))
            Text("vs goal").jiFont(.micro).foregroundStyle(theme.color(.mutedNested))
        }
        .accessibilityHidden(true)
    }

    private func kcalRow(_ total: NutritionDayTotal) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(total.kcal.map { "\(Int($0))" } ?? "—")
                .jiNumeral(.numeralMedium).foregroundStyle(theme.color(.text))
                // Oracle `MacroSummaryCard.tsx` L170 names this row "Calories".
                .accessibilityLabel("Calories")
                .accessibilityValue(total.kcal.map { "\(Int($0)) kcal" } ?? "no data")
                .accessibilityIdentifier("macro-value-kcal")
            Text("kcal").jiFont(.caption).foregroundStyle(theme.color(.muted))
            Spacer()
            Text(goalCopy(total)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                .accessibilityLabel(goalCopy(total))
                .accessibilityIdentifier("macro-goal")
        }
    }

    private func goalCopy(_ total: NutritionDayTotal) -> String {
        guard let kcal = total.kcal, let goal = total.kcalGoal else { return "Goal —" }
        let diff = Int(kcal - goal)
        if diff == 0 { return "on target" }
        return diff > 0 ? "\(diff) over goal" : "\(-diff) kcal remaining"
    }

    private func macroRow(label: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).jiFont(.footnote).foregroundStyle(theme.color(.text))
            Spacer()
            Text(value.map { "\(Int($0))g" } ?? "—").jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                .accessibilityLabel(label)
                .accessibilityValue(value.map { "\(Int($0)) grams" } ?? "no data")
                .accessibilityIdentifier("macro-value-\(label.lowercased())")
        }
        // §2b.2: the macro lines are 44-pt inset-grouped rows, not 20-pt text lines.
        .frame(minHeight: JIRow<EmptyView>.minHeight)
    }
}
