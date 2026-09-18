import Foundation
import HealthKit
import Testing
import JICore
import JIFeatures
import JIHealthKit
import JIPersistence
@testable import JournalInsight

// W7-L3 (P-healthkit-t2-provider): the debug data-source toggle must actually reach the screens.
// `ProviderSwitch` (JIFeatures) owns the choice, `ProviderSelection` (here) owns the two concrete
// providers, and `ProviderStore.provider` is what every screen model is built from. These tests
// pin that chain end to end; `RootTabView`'s one `.onChange(of: ProviderSwitch.shared.revision)`
// site, which drops the cached models so the next render rebuilds them against the swapped
// provider, needs a running view hierarchy and is covered by the wave's simulator smoke.

@Test @MainActor func providerForKindPrefersTheAppleWatchProviderAndFallsBackToTheHub() {
    let hub = MockDataProvider()
    #expect(ProviderSelection.provider(for: .hub, hub: hub, appleWatch: nil) is MockDataProvider)
    // A stale persisted `.appleWatch` on a device that cannot supply it must not strand the app on
    // an empty source (XC CLAUDE.md rule 5).
    #expect(ProviderSelection.provider(for: .appleWatch, hub: hub, appleWatch: nil) is MockDataProvider)

    guard let appleWatch = ProviderSelection.makeAppleWatchProvider() else { return }
    #expect(ProviderSelection.provider(for: .appleWatch, hub: hub, appleWatch: appleWatch) is HealthKitProvider)
    #expect(ProviderSelection.provider(for: .hub, hub: hub, appleWatch: appleWatch) is MockDataProvider)
}

@Test @MainActor func makeAppleWatchProviderTracksHealthDataAvailability() {
    #expect((ProviderSelection.makeAppleWatchProvider() != nil) == HKHealthStore.isHealthDataAvailable())
}

/// The regression this lane's verifier caught: `select` used to move `ProviderSwitch.kind` without
/// anything re-pointing the store, so Today and Recovery kept querying the hub after the flip.
@Test @MainActor func togglingTheSwitchRepointsTheProviderStoreAndTicksTheRevision() throws {
    try #require(HKHealthStore.isHealthDataAvailable(), "T2 needs HealthKit on the test host")
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let hub = MockDataProvider()
    let store = ProviderStore(provider: hub)
    let sut = ProviderSwitch.shared
    defer { sut.select(.hub) }   // `shared` outlives this test — leave it on the default source.

    ProviderSelection.install(store: store, hub: hub, prefs: prefs, using: sut)
    #expect(store.provider is MockDataProvider)
    let afterInstall = sut.revision

    sut.select(.appleWatch)
    #expect(store.provider is HealthKitProvider)
    #expect(sut.revision == afterInstall + 1, "the screens' model cache keys on this tick")

    sut.select(.hub)
    #expect(store.provider is MockDataProvider)
    #expect(sut.revision == afterInstall + 2)
}

/// A reconnect re-installs against the new hub provider; the persisted T2 choice must survive it
/// and the tick must still happen, because every cached model was built from the *old* hub client.
@Test @MainActor func reinstallingOnReconnectRepointsTheStoreAndTicks() throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let store = ProviderStore(provider: MockDataProvider())
    let sut = ProviderSwitch()

    let firstHub = MockDataProvider()
    ProviderSelection.install(store: store, hub: firstHub, prefs: prefs, using: sut)
    let afterFirst = sut.revision

    ProviderSelection.install(store: store, hub: MockDataProvider(), prefs: prefs, using: sut)
    #expect(sut.revision == afterFirst + 1)
    #expect(store.provider is MockDataProvider)
}
