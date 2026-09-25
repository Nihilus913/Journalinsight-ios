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

public nonisolated func kpiCatalogueItems(group: KpiCatalogueGroup, visible: [KpiMetricId], value: (KpiMetricId) -> Double?) -> [JISquareItem] {
    func square(_ id: KpiMetricId, badge: JISquareBadge) -> JISquareItem {
        let def = KpiMetrics.def(id)
        let v = value(id)
        return JISquareItem(id: id.rawValue, label: def.label, systemImage: kpiSymbol(id), tint: metricTintRole(id.rawValue),
                            value: v, decimals: def.decimals, unit: def.unit.isEmpty ? nil : def.unit,
                            status: v == nil ? .missing(.noData) : nil, badge: badge)
    }
    if group == .onToday { return visible.map { square($0, badge: .selected) } }
    let rest = KpiMetricId.allCases.filter { kpiCatalogueGroup($0) == group && !visible.contains($0) }.map { square($0, badge: .add) }
    return group == .nutrition ? rest + kpiCatalogueExtras : rest
}
