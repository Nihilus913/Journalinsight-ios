import Testing
import JICore
@testable import JIFeatures

/// RG-50: My KPIs' "Readiness 88 as of 15 Sep" (the watch's own score) read as Decide's ring
/// "44 Readiness" (the recovery score). The square names its source and keeps its date.
@Suite struct RG50ReadinessLabelTests {
    @Test func readinessSquareNamesTheWatchAndItsDate() {
        let items = kpiCatalogueItems(group: .recovery, visible: [], value: { id in
            id == .readiness ? KpiReading(value: 88, date: "2026-09-15") : nil
        }, today: "2026-10-05", goalCaption: { _, _ in nil }, load: nil, health: [], hub: [])
        let r = try! #require(items.first { $0.id == KpiMetricId.readiness.rawValue })
        #expect(r.label == "Watch readiness")
        #expect(r.goalText?.hasPrefix("as of ") == true)
    }

    @Test func otherSquaresKeepTheirLabel() {
        #expect(kpiSquareLabel(.readiness) == "Watch readiness")
        #expect(kpiSquareLabel(.hrv) == KpiMetrics.def(.hrv).label)
    }
}
