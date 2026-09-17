import SwiftUI
import JICore
import JIDesign

/// (W3a-L2, mirrors `mobile/src/components/nutrition/MacroSummaryCard.tsx`, trimmed to the fields
/// this port's `NutritionProviding` actually carries — protein/carbs/fat *goals* come from a
/// separate `planning/goals` endpoint the RN oracle reads that this screen's contract does not
/// list, so only the kcal goal renders here this wave). Rule 5: a missing value renders "—", never 0.
public struct MacroSummaryCard: View {
    let day: NutritionDayDetail?

    public init(day: NutritionDayDetail?) { self.day = day }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Text("Macros today").font(.caption).foregroundStyle(JIColor.muted).textCase(.uppercase)
                if let day {
                    kcalRow(day.total)
                    Divider().overlay(JIColor.nested)
                    macroRow(label: "Protein", value: day.total.proteinG, color: JIColor.info)
                    macroRow(label: "Carbs", value: day.total.carbsG, color: JIColor.sleep)
                    macroRow(label: "Fat", value: day.total.fatG, color: JIColor.muted)
                } else {
                    Text("No nutrition data yet for this day.").font(.footnote).foregroundStyle(JIColor.muted)
                }
            }
        }
    }

    private func kcalRow(_ total: NutritionDayTotal) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(total.kcal.map { "\(Int($0))" } ?? "—")
                .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(JIColor.text)
            Text("kcal").font(.caption).foregroundStyle(JIColor.muted)
            Spacer()
            Text(goalCopy(total)).font(.caption).foregroundStyle(JIColor.muted)
        }
    }

    private func goalCopy(_ total: NutritionDayTotal) -> String {
        guard let kcal = total.kcal, let goal = total.kcalGoal else { return "Goal —" }
        let diff = Int(kcal - goal)
        if diff == 0 { return "on target" }
        return diff > 0 ? "\(diff) over goal" : "\(-diff) kcal remaining"
    }

    private func macroRow(label: String, value: Double?, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.footnote).foregroundStyle(JIColor.text)
            Spacer()
            Text(value.map { "\(Int($0))g" } ?? "—").font(.footnote.weight(.semibold)).foregroundStyle(JIColor.text)
        }
    }
}
