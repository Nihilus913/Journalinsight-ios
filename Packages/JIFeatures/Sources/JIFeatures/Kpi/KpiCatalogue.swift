import Foundation
import JICore
import JIDesign

/// B-57 W1 KpiList as a catalogue of squares: On Today (ticked), then Recovery / Nutrition / Body.
public nonisolated enum KpiCatalogueGroup: String, CaseIterable, Sendable {
    case onToday = "On Today", recovery = "Recovery", nutrition = "Nutrition", body = "Body"
}

public nonisolated func kpiCatalogueGroup(_ id: KpiMetricId) -> KpiCatalogueGroup {
    switch id {
    case .hrv, .rhr, .sleep, .bodyBattery, .readiness, .acwr: .recovery
    case .kcal, .protein, .carbs, .fat: .nutrition
    case .weight, .steps: .body
    }
}

public nonisolated func isNutritionKpi(_ id: KpiMetricId) -> Bool { kpiCatalogueGroup(id) == .nutrition }

/// Fibre and Sugar (board: the "+" badge every square off Today carries). They are not
/// `KpiMetricId`s, so the badge cannot put them on Today yet. W-FIX7 N-2: their value is Apple
/// Health's newest day (YAZIO writes fibre + sugar to Health), "as of" its day when not today;
/// "— No data" when Health has neither.
public nonisolated let kpiCatalogueExtras: [JISquareItem] = kpiCatalogueExtras(health: [], today: "")

public nonisolated func kpiCatalogueExtras(health: [HealthDailyTotals], today: String) -> [JISquareItem] {
    func square(_ id: String, _ label: String, _ symbol: String, _ field: KeyPath<HealthDailyTotals, Double?>) -> JISquareItem {
        let reading = HealthDailyTotals.latest(field, in: health)
        return JISquareItem(id: id, label: label, systemImage: symbol, value: reading?.value, decimals: 0, unit: reading == nil ? nil : "g",
                            goalText: reading.flatMap { kpiAsOfLabel(valueDate: $0.date, today: today) },
                            status: reading == nil ? .missing(.noData) : nil, badge: .add)
    }
    return [square("fibre", "Fibre", "leaf", \.fiberG), square("sugar", "Sugar", "drop", \.sugarG)]
}

private nonisolated func kpiSymbol(_ id: KpiMetricId) -> String {
    switch id {
    case .hrv: "waveform.path.ecg"; case .rhr: "heart"; case .sleep: "moon"; case .bodyBattery: "battery.75percent"
    case .readiness: "gauge.medium"; case .acwr: "bolt"; case .weight: "scalemass"; case .steps: "figure.walk"
    case .kcal: "flame"; case .protein: "fork.knife"; case .carbs: "leaf"; case .fat: "drop"
    }
}

/// W-FIX1 BUG-05: a KPI square's value and the day it was read on, so a square never presents an
/// older reading (Sep 12's RHR, yesterday's calories) as today's.
public nonisolated struct KpiReading: Sendable, Equatable {
    public let value: Double
    /// `yyyy-MM-dd`; empty for the weight-average fallback, which has no single day.
    public let date: String
    public init(value: Double, date: String) { self.value = value; self.date = date }
}

/// A reading from another day carries "as of Sep 12" under its number (the square's caption).
/// B-57 W2 (B-73): `goalCaption` is the square's goal line for the nutrition ids
/// (`NutritionGoalsSnapshot.caption`: "/ 155 g", "On goal", "Set your goal"); it joins the
/// "as of" label when both exist.
public nonisolated func kpiCatalogueItems(group: KpiCatalogueGroup, visible: [KpiMetricId], value: (KpiMetricId) -> KpiReading?,
                                          today: String = String(Date().ISO8601Format().prefix(10))) -> [JISquareItem] {
    kpiCatalogueItems(group: group, visible: visible, value: value, today: today, goalCaption: { _, _ in nil })
}

public nonisolated func kpiCatalogueItems(group: KpiCatalogueGroup, visible: [KpiMetricId], value: (KpiMetricId) -> KpiReading?,
                                          today: String, goalCaption: (KpiMetricId, Double?) -> String?) -> [JISquareItem] {
    kpiCatalogueItems(group: group, visible: visible, value: value, today: today, goalCaption: goalCaption, load: nil)
}

/// W-FIX5 L1 (WD-2): `load` = the gate-input Load (`RecoveryInsightService.loadReading`). Exactly as
/// on Today (`todayChipsWithLoad`): a current ACWR keeps the Load square; without one the square
/// carries the 7-day minutes with its band caption ("7 d · normal 180–320") instead of "— No data".
public nonisolated func kpiCatalogueItems(group: KpiCatalogueGroup, visible: [KpiMetricId], value: (KpiMetricId) -> KpiReading?,
                                          today: String, goalCaption: (KpiMetricId, Double?) -> String?,
                                          load: RecoveryLoadReading?,
                                          health: [HealthDailyTotals] = HealthDailyTotalsFeed.shared.latest) -> [JISquareItem] {
    func square(_ id: KpiMetricId, badge: JISquareBadge) -> JISquareItem {
        let def = KpiMetrics.def(id)
        let reading = kpiHealthFirstReading(id, hub: value(id), health: health)
        if id == .acwr, reading == nil, let load {
            return JISquareItem(id: id.rawValue, label: kpiLoadMinutesDef.label, systemImage: kpiSymbol(id), tint: metricTintRole(id.rawValue),
                                value: load.minutes.rounded(), decimals: 0, unit: recoveryLoadUnit,
                                goalText: load.caption, status: nil, badge: badge)
        }
        let caption = [goalCaption(id, reading?.value), kpiAsOfLabel(valueDate: reading?.date, today: today)]
            .compactMap { $0 }.joined(separator: " · ")
        return JISquareItem(id: id.rawValue, label: def.label, systemImage: kpiSymbol(id), tint: metricTintRole(id.rawValue),
                            value: reading?.value, decimals: def.decimals, unit: def.unit.isEmpty ? nil : def.unit,
                            goalText: caption.isEmpty ? nil : caption,
                            status: reading == nil ? .missing(.noData) : nil, badge: badge)
    }
    if group == .onToday { return visible.map { square($0, badge: .selected) } }
    let rest = KpiMetricId.allCases.filter { kpiCatalogueGroup($0) == group && !visible.contains($0) }.map { square($0, badge: .add) }
    return group == .nutrition ? rest + kpiCatalogueExtras(health: health, today: today) : rest
}

/// W-FIX7 fixer N-1: My KPIs' Calories / Protein / Carbs / Fat read Apple Health's newest day first
/// (the Fuel / KPI detail source), the hub's YAZIO reading only when it is newer or Health has none.
/// Every other id is the hub's reading unchanged.
public nonisolated func kpiHealthFirstReading(_ id: KpiMetricId, hub: KpiReading?, health: [HealthDailyTotals]) -> KpiReading? {
    let field: KeyPath<HealthDailyTotals, Double?>
    switch id {
    case .kcal: field = \.dietaryKcal
    case .protein: field = \.proteinG
    case .carbs: field = \.carbsG
    case .fat: field = \.fatG
    default: return hub
    }
    guard let h = HealthDailyTotals.latest(field, in: health) else { return hub }
    if let hub, !hub.date.isEmpty, hub.date > h.date { return hub }
    return KpiReading(value: h.value, date: h.date)
}

/// Undated values (fixtures and previews): no "as of" caption.
public nonisolated func kpiCatalogueItems(group: KpiCatalogueGroup, visible: [KpiMetricId], value: (KpiMetricId) -> Double?) -> [JISquareItem] {
    kpiCatalogueItems(group: group, visible: visible, value: { (id: KpiMetricId) -> KpiReading? in value(id).map { KpiReading(value: $0, date: "") } })
}
