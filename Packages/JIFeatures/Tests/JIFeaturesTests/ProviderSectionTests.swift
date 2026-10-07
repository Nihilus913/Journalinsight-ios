import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

// W-OFFLINE OFF-3 (B-50 slice 1): the data-source switch's two build paths, both pinned from a
// Debug test run. `install(honorsPersistedChoice:)` is the seam: `false` is exactly what a Release
// build does (`ProviderSwitch.honorsPersistedChoiceInThisBuild`), so the Release path no longer
// goes untested just because tests always build Debug. The Release *UI* (a Developer row in
// Toby's Settings) is deliberately NOT shipped — Toby 2026-10-04 "no user impact" until the
// 2026-11-01 B-20/B-44 compare.
@Suite struct ProviderSectionTests {
    @MainActor
    private final class ApplyRecorder {
        private(set) var applied: [ProviderKind] = []
        func apply(_ kind: ProviderKind) { applied.append(kind) }
    }

    private func makePrefs() throws -> PrefStore { PrefStore(db: try AppDatabase.inMemory()) }

    /// Leaves a persisted `.appleWatch` behind, as a debug toggle on an earlier launch would.
    @MainActor
    private func persistAppleWatch(in prefs: PrefStore) {
        let earlier = ProviderSwitch()
        earlier.install(prefs: prefs, isAppleWatchAvailable: true, honorsPersistedChoice: true) { _ in }
        earlier.select(.appleWatch)
    }

    @Test @MainActor func theBuildFlagMatchesTheConfiguration() {
        #if DEBUG
        #expect(ProviderSwitch.honorsPersistedChoiceInThisBuild)
        #else
        #expect(!ProviderSwitch.honorsPersistedChoiceInThisBuild)
        #endif
    }

    @Test @MainActor func releaseDefaultsToTheHub() throws {
        let recorder = ApplyRecorder()
        let sut = ProviderSwitch()
        let kind = sut.install(prefs: try makePrefs(), isAppleWatchAvailable: true,
                               honorsPersistedChoice: false, apply: recorder.apply)
        #expect(kind == .hub)
        #expect(recorder.applied == [.hub])
        #expect(sut.revision == 1)
    }

    @Test @MainActor func releaseIgnoresAStalePersistedAppleWatchChoice() throws {
        let prefs = try makePrefs()
        persistAppleWatch(in: prefs)

        let recorder = ApplyRecorder()
        let sut = ProviderSwitch()
        let kind = sut.install(prefs: prefs, isAppleWatchAvailable: true,
                               honorsPersistedChoice: false, apply: recorder.apply)
        #expect(kind == .hub)
        #expect(recorder.applied == [.hub])
    }

    @Test @MainActor func theDeveloperSwitchPersistsAcrossLaunches() throws {
        let prefs = try makePrefs()
        persistAppleWatch(in: prefs)
        #expect(try prefs.get(ProviderSwitch.prefKey, as: ProviderKind.self) == .appleWatch)

        let recorder = ApplyRecorder()
        let next = ProviderSwitch()
        let kind = next.install(prefs: prefs, isAppleWatchAvailable: true,
                                honorsPersistedChoice: true, apply: recorder.apply)
        #expect(kind == .appleWatch)
        #expect(recorder.applied == [.appleWatch])
    }

    @Test(arguments: [true, false]) @MainActor
    func anUnavailableWatchStaysOnTheHub(honorsPersistedChoice: Bool) throws {
        let prefs = try makePrefs()
        persistAppleWatch(in: prefs)

        let recorder = ApplyRecorder()
        let sut = ProviderSwitch()
        let kind = sut.install(prefs: prefs, isAppleWatchAvailable: false,
                               honorsPersistedChoice: honorsPersistedChoice, apply: recorder.apply)
        sut.select(.appleWatch)

        #expect(kind == .hub)
        #expect(sut.kind == .hub)
        #expect(recorder.applied == [.hub])
        #expect(sut.revision == 1)
    }

    @Test @MainActor func hubToAppleWatchToHubEndsWhereItStarted() throws {
        let prefs = try makePrefs()
        let recorder = ApplyRecorder()
        let sut = ProviderSwitch()
        sut.install(prefs: prefs, isAppleWatchAvailable: true, honorsPersistedChoice: true, apply: recorder.apply)

        sut.select(.appleWatch)
        sut.select(.hub)

        #expect(sut.kind == .hub)
        #expect(recorder.applied == [.hub, .appleWatch, .hub])
        #expect(sut.revision == 3, "each flip drops the cached tab models once")
        #expect(try prefs.get(ProviderSwitch.prefKey, as: ProviderKind.self) == .hub)
    }
}
