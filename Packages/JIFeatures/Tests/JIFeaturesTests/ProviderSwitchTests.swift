import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

// W7-L3 (P-healthkit-t2-provider): the debug data-source switch. `revision` is the contract the
// app's model cache keys on — a screen model captures `ProviderStore.provider` at init, so a flip
// that does not tick `revision` leaves Today/Recovery reading the previous source forever. Every
// test below therefore asserts the applied kind AND the tick.

@MainActor
private final class ApplyRecorder {
    private(set) var applied: [ProviderKind] = []
    func apply(_ kind: ProviderKind) { applied.append(kind) }
}

private func makePrefs() throws -> PrefStore { PrefStore(db: try AppDatabase.inMemory()) }

@Test @MainActor func installDefaultsToTheHubAndAppliesItOnce() throws {
    let recorder = ApplyRecorder()
    let sut = ProviderSwitch()
    let kind = sut.install(prefs: try makePrefs(), isAppleWatchAvailable: true, apply: recorder.apply)

    #expect(kind == .hub)
    #expect(sut.kind == .hub)
    #expect(sut.isAppleWatchAvailable)
    #expect(recorder.applied == [.hub])
    #expect(sut.revision == 1)
}

@Test @MainActor func selectingAppleWatchAppliesPersistsAndTicksTheRevision() throws {
    let prefs = try makePrefs()
    let recorder = ApplyRecorder()
    let sut = ProviderSwitch()
    sut.install(prefs: prefs, isAppleWatchAvailable: true, apply: recorder.apply)

    sut.select(.appleWatch)

    #expect(sut.kind == .appleWatch)
    #expect(recorder.applied == [.hub, .appleWatch])
    #expect(sut.revision == 2)
    #expect(try prefs.get(ProviderSwitch.prefKey, as: ProviderKind.self) == .appleWatch)
}

@Test @MainActor func aPersistedAppleWatchChoiceSurvivesTheNextInstall() throws {
    let prefs = try makePrefs()
    let first = ProviderSwitch()
    first.install(prefs: prefs, isAppleWatchAvailable: true) { _ in }
    first.select(.appleWatch)

    let recorder = ApplyRecorder()
    let second = ProviderSwitch()
    let kind = second.install(prefs: prefs, isAppleWatchAvailable: true, apply: recorder.apply)

    // Debug builds restore the pref; release builds always land on the hub (see `install`).
    #if DEBUG
    #expect(kind == .appleWatch)
    #expect(recorder.applied == [.appleWatch])
    #else
    #expect(kind == .hub)
    #expect(recorder.applied == [.hub])
    #endif
    #expect(second.revision == 1)
}

@Test @MainActor func aPersistedAppleWatchChoiceIsIgnoredWhenTheDeviceCannotSupplyIt() throws {
    let prefs = try makePrefs()
    let first = ProviderSwitch()
    first.install(prefs: prefs, isAppleWatchAvailable: true) { _ in }
    first.select(.appleWatch)

    let recorder = ApplyRecorder()
    let second = ProviderSwitch()
    let kind = second.install(prefs: prefs, isAppleWatchAvailable: false, apply: recorder.apply)

    #expect(kind == .hub)
    #expect(recorder.applied == [.hub])
}

@Test @MainActor func selectingAppleWatchIsRefusedWithoutHealthData() throws {
    let recorder = ApplyRecorder()
    let sut = ProviderSwitch()
    sut.install(prefs: try makePrefs(), isAppleWatchAvailable: false, apply: recorder.apply)

    sut.select(.appleWatch)

    #expect(sut.kind == .hub)
    #expect(recorder.applied == [.hub])
    #expect(sut.revision == 1, "a refused select must not invalidate the screens' models")
}

@Test @MainActor func reselectingTheActiveKindIsANoOp() throws {
    let recorder = ApplyRecorder()
    let sut = ProviderSwitch()
    sut.install(prefs: try makePrefs(), isAppleWatchAvailable: true, apply: recorder.apply)

    sut.select(.hub)

    #expect(recorder.applied == [.hub])
    #expect(sut.revision == 1)
}

@Test @MainActor func switchingBackToTheHubTicksAgain() throws {
    let recorder = ApplyRecorder()
    let sut = ProviderSwitch()
    sut.install(prefs: try makePrefs(), isAppleWatchAvailable: true, apply: recorder.apply)
    sut.select(.appleWatch)

    sut.select(.hub)

    #expect(sut.kind == .hub)
    #expect(recorder.applied == [.hub, .appleWatch, .hub])
    #expect(sut.revision == 3)
}
