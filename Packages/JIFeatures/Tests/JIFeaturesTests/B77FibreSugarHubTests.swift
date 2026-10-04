import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-B77 R-4: My KPIs' Fibre / Sugar squares read the hub's YAZIO per-product sums
// (`/nutrition/daily` days[].fiber_g / sugar_g) when Apple Health has nothing newer — the
// W-FIX7 N-1 Health-first rule the macro squares use. Still display-only (W-FIX11 H2-10).

private let today = "2026-10-04"

private func fibre(_ items: [JISquareItem]) throws -> JISquareItem {
    try #require(items.first { $0.id == "fibre" })
}

@Test func b77HubOnlyFillsFibreWithAsOfCaption() throws {
    let items = kpiCatalogueExtras(health: [], today: today,
                                   hub: [NutritionDailyRow(date: "2026-09-29", fiberG: 24, sugarG: 40)])
    let f = try fibre(items)
    #expect(f.value == 24)
    #expect(f.unit == "g")
    #expect(f.goalText == kpiAsOfLabel(valueDate: "2026-09-29", today: today))
    #expect(f.status == nil)
    #expect(f.badge == .none)
    #expect(items.first { $0.id == "sugar" }?.value == 40)
}

@Test func b77HubNewerThanHealthWins() throws {
    let items = kpiCatalogueExtras(health: [HealthDailyTotals(date: "2026-09-28", fiberG: 12)], today: today,
                                   hub: [NutritionDailyRow(date: "2026-09-29", fiberG: 24)])
    #expect(try fibre(items).value == 24)
}

@Test func b77HealthSameDayOrNewerWins() throws {
    let same = kpiCatalogueExtras(health: [HealthDailyTotals(date: "2026-09-29", fiberG: 12)], today: today,
                                  hub: [NutritionDailyRow(date: "2026-09-29", fiberG: 24)])
    #expect(try fibre(same).value == 12)
    let older = kpiCatalogueExtras(health: [HealthDailyTotals(date: "2026-09-29", fiberG: 12)], today: today,
                                   hub: [NutritionDailyRow(date: "2026-09-28", fiberG: 24)])
    #expect(try fibre(older).value == 12)
    #expect(try fibre(older).goalText == kpiAsOfLabel(valueDate: "2026-09-29", today: today))
}

@Test func b77BothEmptyIsNoData() throws {
    let items = kpiCatalogueExtras(health: [], today: today,
                                   hub: [NutritionDailyRow(date: "2026-09-29", kcalConsumed: 1384)])
    let f = try fibre(items)
    #expect(f.value == nil)
    #expect(f.status == .missing(.noData))
}

@Test func b77CatalogueNutritionGroupPassesHubDays() throws {
    let items = kpiCatalogueItems(group: .nutrition, visible: [], value: { _ in nil }, today: today,
                                  goalCaption: { _, _ in nil }, load: nil, health: [],
                                  hub: [NutritionDailyRow(date: "2026-09-29", fiberG: 5.3, sugarG: 13.8)])
    #expect(try fibre(items).value == 5.3)
}
