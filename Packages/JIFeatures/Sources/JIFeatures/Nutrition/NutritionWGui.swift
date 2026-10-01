import SwiftUI
import Charts
import JICore
import JIDesign

// W-GUI M2 — Nutrition (05) + Meal detail (38): pure copy and the meal row / week-bar shapes.
// View models untouched (W2 / B-73 own the numbers).

/// One meal as a timeline row: "Breakfast" · the item names · "546 kcal · 50 g P".
public nonisolated struct MealTimelineRow: Equatable, Sendable {
    public let title: String, subtitle: String, trailing: String
}

public nonisolated func mealTimelineRow(slot: String, items: [NutritionMealItem]) -> MealTimelineRow {
    let detail = mealDetail(slot: slot, items: items)
    let names = items.map(\.name).filter { !$0.isEmpty }
    let subtitle = names.isEmpty ? "— \(JIMissingReason.noData.rawValue)" : names.joined(separator: ", ")
    let kcal = detail.kcal.map { "\(nutritionWholeText($0)) kcal" }
    let protein = detail.protein.map { "\(nutritionWholeText($0)) g P" }
    let trailing = [kcal, protein].compactMap { $0 }.joined(separator: " · ")
    return MealTimelineRow(title: detail.title, subtitle: subtitle, trailing: trailing.isEmpty ? "—" : trailing)
}

/// The ±5 % band around the user's kcal goal (mockup 05 "shaded = ±5 % of your goal"); nil without a goal.
public nonisolated func nutritionWeekBand(goal: Double?) -> ClosedRange<Double>? {
    guard let goal, goal.isFinite, goal > 0 else { return nil }
    return (goal * 0.95)...(goal * 1.05)
}

/// W-FIX11 H2-13: the average of the logged days in the bars' own window (the newest 7 rows) before
/// today — "Avg 1431 kcal · 2 logged days before today"; nil when none is logged. It used to average
/// a day outside the bars and say "today so far" while leaving today out.
public nonisolated func nutritionWeekAverageText(days: [NutritionDailyRow], today: String) -> String? {
    let window = days.sorted { $0.date < $1.date }.suffix(7)
    let logged = window.filter { $0.date < today }.compactMap(\.kcalConsumed)
    guard !logged.isEmpty else { return nil }
    let avg = logged.reduce(0, +) / Double(logged.count)
    return "Avg \(nutritionWholeText(avg)) kcal · \(logged.count) logged day\(logged.count == 1 ? "" : "s") before today"
}

public nonisolated let nutritionGoalAlignCaption = "Logging stays in YAZIO; JI reads, never writes. Your kcal goal comes from the deficit you declared in Goals: keep YAZIO\u{2019}s goal aligned with it."
public nonisolated let mealDetailYazioCaption = "To change it, edit the entry in YAZIO; JI updates on the next sync. JI does not log or edit food."

/// W-GUI M2 (mockup 05): the week's kcal as bars from zero with the ±5 % goal band and the goal
/// line (S1 sum-metric grammar). A day without a logged total draws no bar (never a zero).
struct NutritionWeekBars: View {
    let days: [NutritionDailyRow]
    let goal: Double?
    private let theme = JITheme.native
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120

    private var sorted: [NutritionDailyRow] { days.sorted { $0.date < $1.date }.suffix(7) }

    var body: some View {
        VStack(alignment: .leading, spacing: JISpacing.s2) {
            Chart {
                if let band = nutritionWeekBand(goal: goal) {
                    RectangleMark(yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                        .foregroundStyle(theme.color(.mutedNested).opacity(0.28))
                    RuleMark(y: .value("Goal", goal ?? 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(theme.color(.muted))
                }
                ForEach(sorted, id: \.date) { day in
                    if let kcal = day.kcalConsumed {
                        BarMark(x: .value("Day", nutritionDayParts(day.date)?.weekday ?? day.date), y: .value("kcal", kcal))
                            .foregroundStyle(theme.color(nutritionKcalTintRole))
                            .cornerRadius(4)
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: height)
            .accessibilityLabel("Last 7 days against your goal")
            Text(goal.map { "shaded = ±5 % of your \(nutritionWholeText($0)) goal" } ?? "no goal set · optional")
                .jiFont(.caption).foregroundStyle(theme.color(.muted))
        }
    }
}
