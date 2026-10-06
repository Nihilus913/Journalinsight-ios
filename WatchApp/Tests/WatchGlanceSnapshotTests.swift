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
        // Isolated watch-local suite: the test host IS the watch app, whose `.standard` may hold a
        // wire copy (W-B78) from an earlier launch.
        let store = WatchSnapshotStore(suiteName: suiteName, local: isolatedLocal(), reloadTimelines: {})
        store.refresh()
        return (store, suiteName)
    }

    /// A fresh, empty watch-local suite (never `.standard`).
    static func isolatedLocal() -> UserDefaults {
        UserDefaults(suiteName: "ji.watch.local.tests.\(UUID().uuidString)")!
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
        let store = WatchSnapshotStore(suiteName: suiteName, local: Self.isolatedLocal(), reloadTimelines: {})
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        #expect(store.snapshot == nil)
        #expect(verdictGlanceAccessibilityLabel(store.snapshot) == "Verdict, no data yet")
    }

    // MARK: - W-B78 B78-3: phone → watch WatchConnectivity receive

    /// A fresh store with an empty App-Group suite and an injected watch-local suite (stands in
    /// for `UserDefaults.standard` so the tests never touch the real one).
    @MainActor
    static func wireStore(localSuite: String, reloads: Counter = Counter()) -> WatchSnapshotStore {
        WatchSnapshotStore(
            suiteName: "ji.watch.glance.tests.group.\(UUID().uuidString)",
            local: UserDefaults(suiteName: localSuite)!,
            reloadTimelines: { reloads.count += 1 })
    }

    final class Counter: @unchecked Sendable { var count = 0 }

    @Test @MainActor
    func appliedWireBytesPopulateAllThreeGlances() throws {
        let localSuite = "ji.watch.local.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: localSuite)?.removePersistentDomain(forName: localSuite) }
        let reloads = Counter()
        let store = Self.wireStore(localSuite: localSuite, reloads: reloads)
        #expect(store.snapshot == nil)

        #expect(store.apply(try SnapshotWire.encode(Self.makeSnapshot())))
        #expect(verdictGlanceAccessibilityLabel(store.snapshot) == "Verdict GO Full-upper session")
        #expect(store.snapshot?.readiness == 82.0)
        #expect(store.snapshot?.kpis.map(kpiValueText) == ["61 ms", "48 bpm", "—"])
        #expect(reloads.count == 1) // VerdictComplication reload on receive only
    }

    @Test @MainActor
    func receivedApplicationContextIsApplied() throws {
        let localSuite = "ji.watch.local.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: localSuite)?.removePersistentDomain(forName: localSuite) }
        let store = Self.wireStore(localSuite: localSuite)
        let context: [String: Any] = [SnapshotWire.key: try SnapshotWire.encode(Self.makeSnapshot()), "strengthPlan": Data("{}".utf8)]

        #expect(store.apply(context: context))
        #expect(store.snapshot == Self.makeSnapshot())
        #expect(!store.apply(context: ["strengthPlan": Data("{}".utf8)])) // no snapshot key → nothing
        #expect(store.snapshot == Self.makeSnapshot())
    }

    @Test @MainActor
    func relaunchReadsTheStoredWatchLocalCopy() throws {
        let localSuite = "ji.watch.local.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: localSuite)?.removePersistentDomain(forName: localSuite) }
        _ = Self.wireStore(localSuite: localSuite).apply(try SnapshotWire.encode(Self.makeSnapshot()))

        // Offline relaunch: a new store, no phone, same watch-local defaults.
        let relaunched = Self.wireStore(localSuite: localSuite)
        #expect(relaunched.snapshot == Self.makeSnapshot())
        relaunched.refresh()
        #expect(relaunched.snapshot == Self.makeSnapshot())
    }

    @Test @MainActor
    func garbageIsIgnoredAndKeepsTheLastGoodCopy() throws {
        let localSuite = "ji.watch.local.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: localSuite)?.removePersistentDomain(forName: localSuite) }
        let reloads = Counter()
        let store = Self.wireStore(localSuite: localSuite, reloads: reloads)
        _ = store.apply(try SnapshotWire.encode(Self.makeSnapshot()))

        #expect(!store.apply(Data("not a snapshot".utf8)))
        #expect(store.snapshot == Self.makeSnapshot())
        #expect(Self.wireStore(localSuite: localSuite).snapshot == Self.makeSnapshot())
        #expect(reloads.count == 1)
    }

    @Test @MainActor
    func wireCopyWinsOverTheAppGroupCopy() throws {
        let localSuite = "ji.watch.local.tests.\(UUID().uuidString)"
        let groupSuite = "ji.watch.glance.tests.group.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: localSuite)?.removePersistentDomain(forName: localSuite)
            UserDefaults(suiteName: groupSuite)?.removePersistentDomain(forName: groupSuite)
        }
        var old = Self.makeSnapshot(); old.verdictWord = "REST"
        SnapshotStore(suiteName: groupSuite).write(old)
        let store = WatchSnapshotStore(suiteName: groupSuite, local: UserDefaults(suiteName: localSuite)!, reloadTimelines: {})
        #expect(store.snapshot?.verdictWord == "REST") // App-Group fallback (sim / pre-B-78)
        _ = store.apply(try SnapshotWire.encode(Self.makeSnapshot()))
        store.refresh()
        #expect(store.snapshot?.verdictWord == "GO")
    }

    @Test
    func debugSeamFeedsAFakeSnapshotOnlyWhenAsked() throws {
        #expect(WatchSnapshotStore.debugFakeSnapshotData(environment: [:]) == nil)
        let data = try #require(WatchSnapshotStore.debugFakeSnapshotData(environment: ["WATCH_FAKE_SNAPSHOT": "1"]))
        let snap = try #require(SnapshotWire.decode(data))
        #expect(!snap.verdictWord.isEmpty)
        #expect(snap.readiness != nil)
        #expect(!snap.kpis.isEmpty)
    }
}
