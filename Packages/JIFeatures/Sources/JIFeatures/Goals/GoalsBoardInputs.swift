import Foundation
import JICore

/// W-FIX12 F12-1 (H2-23): the pure builder behind More › Goals' board inputs. Each metric reads its
/// LATEST reading with the day it was taken — the board used to read yesterday's row only, so a
/// weigh-in four days ago showed nothing (or an undated number) while Today/More said "as of 29 Sep".
/// Weight counts today's weigh-in; calories, protein and steps read the newest COMPLETE day (before
/// today) so a half-logged today is never compared against a whole-day goal.
public nonisolated enum GoalsBoardInputs {
    public static func build(goals: Goals?, dailyRows: [DailyKpiRow], gateAverages: GateAverages?,
                             nutrition: [NutritionDailyRow], energyDays: [EnergyDay],
                             avgDeficit7d: Double?, trackingDays: Int, today: String) -> GoalsBoardInput {
        let weight = KpiMetrics.latest(for: .weight, recovery: [], nutrition: [], dailyRows: dailyRows, gateAverages: gateAverages)
        let done = { (date: String) in date < today }
        let kcal = newest(nutrition.filter { done($0.date) }.map { ($0.date, $0.kcalConsumed) })
            ?? newest(energyDays.filter { done($0.date) }.map { ($0.date, $0.kcalConsumed) })
        let protein = newest(nutrition.filter { done($0.date) }.map { ($0.date, $0.proteinG) })
        let steps = newest(dailyRows.filter { done($0.date) }.map { ($0.date, $0.values["steps"].flatMap { $0 }) })
        return GoalsBoardInput(goals: goals, latestKg: weight?.value, avgDeficit7d: avgDeficit7d, trackingDays: trackingDays,
                               yesterdayKcal: kcal?.value, yesterdayProteinG: protein?.value, yesterdaySteps: steps?.value,
                               latestKgDate: weight?.date, kcalDate: kcal?.date, proteinDate: protein?.date, stepsDate: steps?.date,
                               today: today)
    }

    /// " · 29 Sep" / " · today"; "" when the reading has no single day.
    public static func dateSuffix(_ iso: String?, today: String?) -> String {
        guard let iso, iso.count >= 10 else { return "" }
        let day = String(iso.prefix(10))
        if day == today { return " · today" }
        guard let date = DayKey(iso: day)?.startDate(in: .gmt) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB"); f.timeZone = .gmt
        f.dateFormat = "d MMM"
        return " · " + f.string(from: date)
    }

    /// The newest non-nil, finite value with its day.
    private static func newest(_ rows: [(String, Double?)]) -> (date: String, value: Double)? {
        rows.sorted { $0.0 > $1.0 }.lazy.compactMap { row in row.1.flatMap { $0.isFinite ? (row.0, $0) : nil } }.first
    }
}
