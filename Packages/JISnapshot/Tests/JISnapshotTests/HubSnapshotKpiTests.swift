import Foundation
import Testing
import JICore
@testable import JISnapshot

/// W-B34 L1 (B-34/B-36): the snapshot's new optional `SnapshotKPI.id` / `HubSnapshot.allKpis`
/// fields and the `kpi(_:)` lookup the configurable KPI widget reads.
@Suite
struct HubSnapshotKpiTests {
    /// A snapshot exactly as a pre-W-B34 build wrote it to the App Group (default `JSONEncoder`,
    /// dates as seconds since 2001) — no `id` on any KPI, no `allKpis` key at all.
    static let preB34JSON = #"""
    {"verdictWord":"GO","verdictSession":"Full session","verdictTone":"go","verdictDate":"2026-09-13",
     "readiness":82.5,"kpis":[{"label":"HRV","value":61,"unit":"ms"},{"label":"Sleep"}],
     "fetchedAt":779000000,"lastSync":778999000}
    """#

    @Test
    func oldSnapshotWithoutNewFieldsStillDecodes() throws {
        let decoded = try JSONDecoder().decode(HubSnapshot.self, from: Data(Self.preB34JSON.utf8))
        #expect(decoded.verdictWord == "GO")
        #expect(decoded.allKpis == nil)
        #expect(decoded.kpis.count == 2)
        #expect(decoded.kpis.allSatisfy { $0.id == nil })
        #expect(decoded.kpis[1].value == nil)
        // No id anywhere → the widget lookup finds nothing (renders "—"), never a label match.
        #expect(decoded.kpi(.hrv) == nil)
    }

    @Test
    func kpiLookupPrefersAllKpisThenFallsBackToChipsById() {
        let snapshot = HubSnapshot(
            verdictWord: "GO", verdictSession: "Full session", verdictTone: "go", verdictDate: nil,
            readiness: 80,
            kpis: [
                SnapshotKPI(id: .hrv, label: "HRV chip", value: 1, unit: "ms"),
                SnapshotKPI(id: .steps, label: "Steps chip", value: 9000, unit: nil),
            ],
            allKpis: [
                SnapshotKPI(id: .hrv, label: "HRV", value: 61, unit: "ms"),
                SnapshotKPI(id: .weight, label: "Weight", value: nil, unit: "kg"),
            ],
            fetchedAt: Date(timeIntervalSince1970: 0), lastSync: nil
        )
        #expect(snapshot.kpi(.hrv)?.value == 61)          // allKpis wins over the chip
        #expect(snapshot.kpi(.steps)?.value == 9000)      // not in allKpis → chips by id
        #expect(snapshot.kpi(.weight) != nil)             // present with a nil value
        #expect(snapshot.kpi(.weight)?.value == nil)
        #expect(snapshot.kpi(.fat) == nil)                // in neither
    }

    @Test
    func newFieldsRoundTrip() throws {
        let snapshot = HubSnapshot(
            verdictWord: "GO", verdictSession: "s", verdictTone: "go", verdictDate: nil, readiness: nil,
            kpis: [],
            allKpis: KpiMetricId.allCases.map { SnapshotKPI(id: $0, label: KpiMetrics.def($0).label, value: nil, unit: nil) },
            fetchedAt: Date(timeIntervalSince1970: 0), lastSync: nil
        )
        let decoded = try JSONDecoder().decode(HubSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
        #expect(decoded.allKpis?.count == 12)
        #expect(decoded.allKpis?.compactMap(\.id) == KpiMetricId.allCases)
    }
}
