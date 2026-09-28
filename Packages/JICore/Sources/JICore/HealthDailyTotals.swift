import Foundation
import Observation
import Synchronization

/// B-57 W2 (B-73): one local calendar day of the Health totals JI reads for nutrition and energy.
/// `nil` means Health returned no samples for that type on that day. It is never 0 (XC rule 5).
/// W-FIX7 N-2: + dietary fibre and sugar (YAZIO writes them to Health).
public struct HealthDailyTotals: Codable, Sendable, Equatable {
    public var date: String
    public var basalKcal: Double?
    public var activeKcal: Double?
    public var dietaryKcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var fiberG: Double?
    public var sugarG: Double?

    public init(date: String, basalKcal: Double? = nil, activeKcal: Double? = nil, dietaryKcal: Double? = nil,
                proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil, fiberG: Double? = nil, sugarG: Double? = nil) {
        self.date = date; self.basalKcal = basalKcal; self.activeKcal = activeKcal; self.dietaryKcal = dietaryKcal
        self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG; self.fiberG = fiberG; self.sugarG = sugarG
    }

    /// True when Health returned anything at all for this day.
    public var hasAnyValue: Bool {
        [basalKcal, activeKcal, dietaryKcal, proteinG, carbsG, fatG, fiberG, sugarG].contains { $0 != nil }
    }

    /// W-FIX7 N-1: Health holds this day's food (kcal or a macro). Only such a day replaces the
    /// hub's YAZIO row; a day without it keeps YAZIO's (or stays "—").
    public var hasFood: Bool { [dietaryKcal, proteinG, carbsG, fatG].contains { $0 != nil } }

    /// The newest day carrying `field`, with its date (the caller shows "as of" when it isn't today).
    public static func latest(_ field: KeyPath<HealthDailyTotals, Double?>, in rows: [HealthDailyTotals]) -> HealthDatedValue? {
        rows.sorted { $0.date > $1.date }.lazy.compactMap { r in r[keyPath: field].map { HealthDatedValue(value: $0, date: r.date) } }.first
    }
}

/// A Health value and the local day (`yyyy-MM-dd`) it belongs to.
public struct HealthDatedValue: Sendable, Equatable {
    public let value: Double
    public let date: String
    public init(value: Double, date: String) { self.value = value; self.date = date }
}

/// Seam over the on-device Health reader (`JIHealthKit.HKDailyTotalsReader`), so JIFeatures can
/// test against a fake. `days` local calendar days ending TODAY (inclusive), oldest first, one
/// entry per day.
public protocol HealthDailyTotalsProviding: Sendable {
    func dailyTotals(days: Int) async throws -> [HealthDailyTotals]
}

/// W-FIX7 N-1: the last Health totals the phone read (the App's `HealthDailyTotalsAdapter`
/// publishes every successful read, i.e. each foreground). Fuel, Nutrition, Energy and the KPI
/// screens read it, so there is one Health read per foreground, not one per screen. Observable:
/// a view whose body read `latest` re-renders when a fresh read lands. Empty = nothing read yet
/// this launch (the view models fall back to the band's cached totals).
public final class HealthDailyTotalsFeed: Observable, Sendable {
    public static let shared = HealthDailyTotalsFeed()
    private let registrar = ObservationRegistrar()
    private let storage = Mutex<[HealthDailyTotals]>([])

    public init() {}

    public var latest: [HealthDailyTotals] {
        registrar.access(self, keyPath: \.latest)
        return storage.withLock { $0 }
    }

    public func publish(_ rows: [HealthDailyTotals]) {
        registrar.withMutation(of: self, keyPath: \.latest) { storage.withLock { $0 = rows } }
    }
}

// MARK: - W-FIX7 N-1: Apple Health first, the hub's YAZIO rows only for days Health lacks

/// Merged rows keep the hub's order (newest first when the hub sends it so, else oldest first).
private func mergeByDate<Row>(_ hub: [Row], health: [HealthDailyTotals], date: (Row) -> String,
                              replace: (Row, HealthDailyTotals) -> Row, make: (HealthDailyTotals) -> Row) -> [Row] {
    let food = Dictionary(health.filter(\.hasFood).map { ($0.date, $0) }, uniquingKeysWith: { _, b in b })
    let newestFirst = hub.count > 1 && date(hub[0]) > date(hub[hub.count - 1])
    var out = hub.map { row in food[date(row)].map { replace(row, $0) } ?? row }
    let have = Set(hub.map(date))
    out += food.values.filter { !have.contains($0.date) }.map(make)
    return out.sorted { newestFirst ? date($0) > date($1) : date($0) < date($1) }
}

extension NutritionDailyRow {
    /// Health's kcal + macros for each day Health has food; the goal and meal count stay the hub's.
    public static func mergingHealth(_ hub: [NutritionDailyRow], health: [HealthDailyTotals]) -> [NutritionDailyRow] {
        mergeByDate(hub, health: health, date: \.date,
                    replace: { r, h in
                        NutritionDailyRow(date: r.date, kcalConsumed: h.dietaryKcal, kcalGoal: r.kcalGoal, proteinG: h.proteinG,
                                          carbsG: h.carbsG, fatG: h.fatG, mealsLogged: r.mealsLogged)
                    },
                    make: { h in NutritionDailyRow(date: h.date, kcalConsumed: h.dietaryKcal, proteinG: h.proteinG, carbsG: h.carbsG, fatG: h.fatG) })
    }
}

extension NutritionDayDetail {
    /// The day's total from Health when Health has the day; the meals (items, breakdown) stay
    /// YAZIO's — Health has day sums only. A Health-only day has a total and no meals.
    public static func mergingHealth(_ hub: NutritionDayDetail?, date: String, health: [HealthDailyTotals]) -> NutritionDayDetail? {
        guard let h = health.last(where: { $0.date == date && $0.hasFood }) else { return hub }
        let total = NutritionDayTotal(kcal: h.dietaryKcal, kcalGoal: hub?.total.kcalGoal, proteinG: h.proteinG, carbsG: h.carbsG,
                                      fatG: h.fatG, mealsLogged: hub?.total.mealsLogged)
        return NutritionDayDetail(date: date, total: total, breakdown: hub?.breakdown ?? NutritionDayBreakdown(), items: hub?.items ?? [:])
    }
}

extension EnergyDay {
    /// Health intake for each day Health has food; the deficit is recomputed from it exactly as
    /// the hub does (`app/nutrition/energy.py`: tdee − kcal, % of tdee, classified on the
    /// corrected %). No TDEE → no deficit (never 0).
    public static func mergingHealth(_ hub: [EnergyDay], health: [HealthDailyTotals]) -> [EnergyDay] {
        func withIntake(_ d: EnergyDay, _ kcal: Double?) -> EnergyDay {
            var out = EnergyDay(date: d.date, kcalConsumed: kcal, tdeeRaw: d.tdeeRaw, tdeeCorrected: d.tdeeCorrected, mealsLogged: d.mealsLogged)
            guard let kcal else { return out }
            func r1(_ x: Double) -> Double { (x * 10).rounded(.toNearestOrEven) / 10 }
            if let t = d.tdeeRaw {
                out.deficitRaw = r1(t - kcal)
                out.deficitPctRaw = t != 0 ? r1((t - kcal) / t * 100) : nil
            }
            if let t = d.tdeeCorrected, d.tdeeRaw != nil {
                out.deficitCorrected = r1(t - kcal)
                out.deficitPctCorrected = t != 0 ? r1((t - kcal) / t * 100) : nil
                out.deficitClass = classifyDeficit(out.deficitPctCorrected)
            }
            return out
        }
        return mergeByDate(hub, health: health, date: \.date,
                           replace: { d, h in withIntake(d, h.dietaryKcal) },
                           make: { h in EnergyDay(date: h.date, kcalConsumed: h.dietaryKcal) })
    }

    /// `app/nutrition/energy.py::classify_deficit`.
    static func classifyDeficit(_ pct: Double?) -> String? {
        guard let pct else { return nil }
        if pct <= 0 { return "surplus" }
        if pct <= 15 { return "mild" }
        if pct <= 22 { return "moderate" }
        if pct <= 28 { return "aggressive" }
        return "dangerous"
    }
}

extension DailyKpiRow {
    public init(date: String, values: [String: Double?]) { self.date = date; self.values = values }

    /// The gate's daily rows with Health's food (`kcal_consumed`, `protein_g`, `carbs_g`, `fat_g`)
    /// on each day Health has food; every other key (steps, weight, …) stays the hub's.
    public static func mergingHealth(_ hub: [DailyKpiRow], health: [HealthDailyTotals]) -> [DailyKpiRow] {
        func food(_ h: HealthDailyTotals) -> [String: Double?] {
            ["kcal_consumed": h.dietaryKcal, "protein_g": h.proteinG, "carbs_g": h.carbsG, "fat_g": h.fatG]
        }
        return mergeByDate(hub, health: health, date: \.date,
                           replace: { r, h in DailyKpiRow(date: r.date, values: r.values.merging(food(h)) { _, new in new }) },
                           make: { h in DailyKpiRow(date: h.date, values: food(h)) })
    }
}
