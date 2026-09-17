import Foundation
import Testing
import JISnapshot
@testable import WatchApp

/// B-10: the watch app previously shipped with no committed test at all.
/// These seed a `HubSnapshot` through the same App-Group `SnapshotStore`
/// path `WatchSnapshotStore` reads from, then assert the values each
/// glance renders through — `verdictGlanceAccessibilityLabel` (VerdictGlance),
/// `.readiness` (ReadinessGlance), and `kpiValueText`/`kpiAccessibilityLabel`
/// (MyKpisGlance) — so a regression in any of those glances' rendered
/// strings fails a test, not just a screenshot.
@Suite
struct WatchGlanceSnapshotTests {
    static func makeSnapshot() -> HubSnapshot {
        HubSnapshot(
            verdictWord: "GO",
            verdictSession: "Full-upper session",
            verdictTone: "go",
            verdictDate: "2026-09-17",
            readiness: 82.0,
            kpis: [
                SnapshotKPI(label: "HRV", value: 61, unit: "ms"),
                SnapshotKPI(label: "RHR", value: 48, unit: "bpm"),
                SnapshotKPI(label: "Sleep", value: nil, unit: "h"),
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_757_000_000),
            lastSync: Date(timeIntervalSince1970: 1_757_000_000)
        )
    }

    /// Seeds via `SnapshotStore` (the same suite `WatchSnapshotStore` reads) and returns a
    /// freshly refreshed `WatchSnapshotStore`, cleaning up the ad-hoc suite afterwards.
    static func seededStore(_ snapshot: HubSnapshot) -> (WatchSnapshotStore, suiteName: String) {
        let suiteName = "ji.watch.glance.tests.\(UUID().uuidString)"
        SnapshotStore(suiteName: suiteName).write(snapshot)
        let store = WatchSnapshotStore(suiteName: suiteName)
        store.refresh()
        return (store, suiteName)
    }

    @Test @MainActor
    func seededSnapshotDrivesVerdictGlanceLabel() {
        let seeded = Self.makeSnapshot()
        let (store, suiteName) = Self.seededStore(seeded)
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        #expect(store.snapshot == seeded)
        #expect(verdictGlanceAccessibilityLabel(store.snapshot) == "Verdict GO Full-upper session")
    }

    @Test @MainActor
    func seededSnapshotDrivesReadinessGlanceScore() {
        let seeded = Self.makeSnapshot()
        let (store, suiteName) = Self.seededStore(seeded)
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        // ReadinessGlance renders `ReadinessArcGauge(score: snapshot?.readiness, ...)` directly —
        // asserting the value that reaches the gauge is the model-level check for this glance.
        #expect(store.snapshot?.readiness == 82.0)
    }

    @Test @MainActor
    func seededSnapshotDrivesMyKpisGlanceValues() throws {
        let seeded = Self.makeSnapshot()
        let (store, suiteName) = Self.seededStore(seeded)
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let kpis = try #require(store.snapshot?.kpis)
        #expect(kpis.map(kpiValueText) == ["61 ms", "48 bpm", "—"])
        #expect(kpiAccessibilityLabel(kpis[0]) == "HRV 61 ms")
        // rule 5 / DESIGN-6: a missing value never coerces to a bare unit or 0.
        #expect(kpiAccessibilityLabel(kpis[2]) == "Sleep —")
    }

    @Test @MainActor
    func noSnapshotRendersNoDataYetNotAZero() {
        let suiteName = "ji.watch.glance.tests.empty.\(UUID().uuidString)"
        let store = WatchSnapshotStore(suiteName: suiteName)
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        #expect(store.snapshot == nil)
        #expect(verdictGlanceAccessibilityLabel(store.snapshot) == "Verdict, no data yet")
    }
}
