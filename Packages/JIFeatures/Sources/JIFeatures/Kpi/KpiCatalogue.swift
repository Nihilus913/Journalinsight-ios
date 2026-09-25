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

/// Squares with no source on the phone yet (board: "— / No data" with the "+" badge every square
/// off Today carries). They are not `KpiMetricId`s, so the badge cannot put them on Today yet.
public nonisolated let kpiCatalogueExtras: [JISquareItem] = [
    JISquareItem(id: "fibre", label: "Fibre", systemImage: "leaf", value: nil, status: .missing(.noData), badge: .add),
    JISquareItem(id: "sugar", label: "Sugar", systemImage: "drop", value: nil, status: .missing(.noData), badge: .add),
]

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
    func square(_ id: KpiMetricId, badge: JISquareBadge) -> JISquareItem {
        let def = KpiMetrics.def(id)
        let reading = value(id)
        let caption = [goalCaption(id, reading?.value), kpiAsOfLabel(valueDate: reading?.date, today: today)]
            .compactMap { $0 }.joined(separator: " · ")
        return JISquareItem(id: id.rawValue, label: def.label, systemImage: kpiSymbol(id), tint: metricTintRole(id.rawValue),
                            value: reading?.value, decimals: def.decimals, unit: def.unit.isEmpty ? nil : def.unit,
                            goalText: caption.isEmpty ? nil : caption,
                            status: reading == nil ? .missing(.noData) : nil, badge: badge)
    }
    if group == .onToday { return visible.map { square($0, badge: .selected) } }
    let rest = KpiMetricId.allCases.filter { kpiCatalogueGroup($0) == group && !visible.contains($0) }.map { square($0, badge: .add) }
    return group == .nutrition ? rest + kpiCatalogueExtras : rest
}

/// Undated values (fixtures and previews): no "as of" caption.
public nonisolated func kpiCatalogueItems(group: KpiCatalogueGroup, visible: [KpiMetricId], value: (KpiMetricId) -> Double?) -> [JISquareItem] {
    kpiCatalogueItems(group: group, visible: visible, value: { (id: KpiMetricId) -> KpiReading? in value(id).map { KpiReading(value: $0, date: "") } })
}
