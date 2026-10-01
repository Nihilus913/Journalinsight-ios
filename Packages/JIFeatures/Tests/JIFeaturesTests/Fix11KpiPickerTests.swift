import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-FIX11 H2-10 (bug hunt 2026-10-01): the On Today picker showed a green "+" that did nothing —
// on every square once Today held 8, and always on the display-only Fibre / Sugar.

private let eight: [KpiMetricId] = Array(KpiMetricId.allCases.prefix(KpiSelection.maxSelected))

@Test func atTheCapNoSquareOffersPlus() {
    for group in KpiCatalogueGroup.allCases where group != .onToday {
        let items = kpiCatalogueItems(group: group, visible: eight, value: { _ in nil }, today: "2026-10-01",
                                      goalCaption: { _, _ in nil }, load: nil, health: [])
        #expect(items.allSatisfy { $0.badge != .add }, "\(group)")
    }
    #expect(kpiTodayFullNote(count: 8) == "Today is full (8). Untick one to add another.")
    #expect(kpiTodayFullNote(count: 7) == nil)
}

@Test func displayOnlySquaresNeverOfferPlus() {
    #expect(kpiCatalogueExtras(health: [], today: "2026-10-01").allSatisfy { $0.badge == .none })
}

@Test func belowTheCapPlusStays() {
    let items = kpiCatalogueItems(group: .recovery, visible: [.kcal, .protein, .carbs], value: { _ in nil }, today: "2026-10-01",
                                  goalCaption: { _, _ in nil }, load: nil, health: [])
    #expect(items.contains { $0.badge == .add })
}
