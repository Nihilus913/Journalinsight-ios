import Foundation
import Testing
@testable import JISnapshot

@Suite
struct SnapshotStoreTests {
    static func makeSnapshot() -> HubSnapshot {
        HubSnapshot(
            verdictWord: "REDUCED",
            verdictSession: "Easy session",
            verdictTone: "amber",
            verdictDate: "2026-09-13",
            readiness: 55.0,
            kpis: [SnapshotKPI(label: "Steps", value: 8123, unit: "steps")],
            fetchedAt: Date(timeIntervalSince1970: 1_757_000_000),
            lastSync: nil
        )
    }

    @Test
    func roundTripThroughAppGroupSuite() {
        let suiteName = "ji.snapshot.tests.\(UUID().uuidString)"
        let store = SnapshotStore(suiteName: suiteName)
        let snapshot = Self.makeSnapshot()

        store.write(snapshot)
        let readBack = store.read()

        #expect(readBack == snapshot)

        // Clean up so the test suite doesn't leak into the host's defaults.
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test
    func missingGroupReadReturnsNilAndWriteDoesNotCrash() {
        // A genuinely unavailable app group (missing entitlement, e.g.) surfaces as `nil`
        // UserDefaults, not a bogus suite name — `UserDefaults(suiteName: "")` is not
        // guaranteed to return nil on every toolchain (on the Xcode 27 RC it resolves to the
        // real standard-defaults domain and the write silently "succeeds" there instead).
        // Inject the unavailable case directly so this test exercises SnapshotStore's own
        // nil-handling rather than a suite-name-validation quirk.
        let store = SnapshotStore(defaults: nil)

        #expect(store.read() == nil)

        // Must not crash / force-unwrap.
        store.write(Self.makeSnapshot())

        // Still nothing readable back out for this identity.
        #expect(store.read() == nil)
    }
}
