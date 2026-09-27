import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-GUI R4 — My KPIs (23): headers carry the count, copy stays honest, the detail map is unchanged.
@Test func kpiListHeadersAndCopy() {
    #expect(kpiListGroupHeader(.onToday, count: 6) == "On Today · 6")
    #expect(kpiListGroupHeader(.recovery, count: 3) == KpiCatalogueGroup.recovery.rawValue)
    #expect(kpiListCaption.hasPrefix("Any square can go on a widget."))
    #expect(kpiListSubtitle == "Every metric is a square. Ticked ones sit on Today.")
    #expect(kpiListDetailMetric("hrv") == "hrv")          // BUG-21: a square still opens its detail
    #expect(kpiListDetailMetric("fibre") == nil)
    #expect(squareTileFamily(catalog: true).base == 104)
}
