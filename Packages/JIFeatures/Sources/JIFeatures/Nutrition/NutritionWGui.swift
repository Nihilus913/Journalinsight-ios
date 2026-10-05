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

/// RG-43: one fixed slot per day of the 7 days ending `today` (x = ISO date, so every slot is its
/// own category; label = weekday initial). A day without a logged total keeps its slot, no bar.
public nonisolated struct NutritionWeekSlot: Equatable, Sendable {
    public let date: String
    public let label: String
    public let kcal: Double?
}

public nonisolated func nutritionWeekSlots(days: [NutritionDailyRow], today: String) -> [NutritionWeekSlot] {
    guard let end = trainingStripDate(today) else { return [] }
    let byDate = Dictionary(days.map { ($0.date, $0.kcalConsumed) }, uniquingKeysWith: { a, b in a ?? b })
    return (0..<7).reversed().compactMap { back -> NutritionWeekSlot? in
        guard let d = trainingStripCalendar.date(byAdding: .day, value: -back, to: end) else { return nil }
        let iso = trainingStripISO(d)
        let label = nutritionDayParts(iso).map { String($0.weekday.prefix(1)) } ?? iso
        return NutritionWeekSlot(date: iso, label: label, kcal: byDate[iso] ?? nil)
    }
}

/// RG-43: the y axis top — always above the ±5 % band so the band is drawn even on low weeks.
public nonisolated func nutritionWeekYTop(kcals: [Double], goal: Double?) -> Double {
    let bandTop = nutritionWeekBand(goal: goal)?.upperBound ?? 0
    let top = max(kcals.filter(\.isFinite).max() ?? 0, bandTop)
    return top > 0 ? top * 1.1 : 2000
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
    var today: String = energyTodayISO()
    private let theme = JITheme.native
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120

    /// RG-43: seven fixed slots (a single logged day used to fill the whole width).
    private var slots: [NutritionWeekSlot] { nutritionWeekSlots(days: days, today: today) }

    var body: some View {
        VStack(alignment: .leading, spacing: JISpacing.s2) {
            Chart {
                ForEach(slots, id: \.date) { slot in
                    if let kcal = slot.kcal {
                        BarMark(x: .value("Day", slot.date), y: .value("kcal", kcal), width: .ratio(0.6))
                            .foregroundStyle(theme.color(nutritionKcalTintRole))
                            .cornerRadius(4)
                    }
                }
                if let goal, nutritionWeekBand(goal: goal) != nil {
                    RuleMark(y: .value("Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(theme.color(.muted))
                }
            }
            .chartXScale(domain: slots.map(\.date))
            .chartYScale(domain: 0...nutritionWeekYTop(kcals: slots.compactMap(\.kcal), goal: goal))
            .chartXAxis {
                AxisMarks(values: slots.map(\.date)) { value in
                    AxisValueLabel {
                        if let iso = value.as(String.self) { Text(slots.first { $0.date == iso }?.label ?? "") }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            // RG-43: the ±5 % band drawn across the whole plot (a y-only RectangleMark on a
            // categorical x axis was not drawn).
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let band = nutritionWeekBand(goal: goal), let plot = proxy.plotFrame,
                       let yHigh = proxy.position(forY: band.upperBound), let yLow = proxy.position(forY: band.lowerBound) {
                        let frame = geo[plot]
                        Rectangle()
                            .fill(theme.color(.mutedNested).opacity(0.28))
                            .frame(width: frame.width, height: max(1, yLow - yHigh))
                            .position(x: frame.midX, y: frame.minY + (yHigh + yLow) / 2)
                            .accessibilityIdentifier("nutrition-week-band")
                    }
                }
            }
            .frame(height: height)
            .accessibilityLabel("Last 7 days against your goal")
            Text(goal.map { "shaded = ±5 % of your \(nutritionWholeText($0)) goal" } ?? "no goal set · optional")
                .jiFont(.caption).foregroundStyle(theme.color(.muted))
        }
    }
}
