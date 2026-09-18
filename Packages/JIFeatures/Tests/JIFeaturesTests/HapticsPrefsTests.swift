import Foundation
import Testing
import JIDesign
import JIPersistence
@testable import JIFeatures

// W8-L1 (P-haptics). Port of `mobile/__tests__/haptics/hapticsPrefs.test.ts` (13) onto
// `HapticsPrefsStore` over `PrefStore` (the RN in-memory `cache` table fake → `AppDatabase.
// inMemory()`), with RN's module-level cache = a private `JIHapticDispatcher` per test (never the
// shared one — tests run in parallel) and `useHapticsEnabled`/`useHapticsIntensity` =
// `HapticsViewModel`. Plus the Settings registry line and the "Feel it" / slider seams.

@MainActor
private final class Fixture {
    let store: PrefStore
    let dispatcher = JIHapticDispatcher(player: nil, fallback: NoopFallback())
    let fallback: NoopFallback
    init() throws {
        store = PrefStore(db: try AppDatabase.inMemory())
        fallback = dispatcher.fallback as! NoopFallback
        dispatcher.marker = { _ in }
    }
    /// `__resetHapticsPrefsForTests` — a cold start: fresh cache, same db.
    func coldStart() { dispatcher.resetForTests() }
    func load() { HapticsPrefsStore.warm(from: store, into: dispatcher) }
    var enabledSync: Bool { dispatcher.prefs.enabled }
    var intensitySync: Int { dispatcher.prefs.intensity }
    func setEnabled(_ v: Bool) throws { try HapticsPrefsStore.setEnabled(v, store: store, dispatcher: dispatcher) }
    func setIntensity(_ v: Double) throws { try HapticsPrefsStore.setIntensity(v, store: store, dispatcher: dispatcher) }
}

@MainActor
final class NoopFallback: JIHapticFallbackPlayer {
    var calls: [JIHapticFallback] = []
    func play(_ fallback: JIHapticFallback) { calls.append(fallback) }
}

// MARK: enabled

@Test @MainActor func defaultsToEnabledBeforeAnythingSaved() throws {
    let f = try Fixture()
    #expect(HapticsPrefsStore.load(from: f.store).enabled == true)
    #expect(JIHapticsPrefs.defaultEnabled == true)
}

@Test @MainActor func enabledSyncReadsTheDefaultThenCatchesUpOnceLoaded() throws {
    let f = try Fixture()
    try f.setEnabled(false)
    f.coldStart()
    #expect(f.enabledSync == true)   // fails OPEN until the load catches up
    f.load()
    #expect(f.enabledSync == false)
}

@Test @MainActor func setEnabledUpdatesTheSyncCacheImmediately() throws {
    let f = try Fixture()
    try f.setEnabled(false)
    #expect(f.enabledSync == false)
    #expect(try f.store.get(HapticsPrefsStore.enabledKey, as: Bool.self) == false)
}

@Test @MainActor func enabledRoundTripPersistsAcrossASimulatedRestart() throws {
    let f = try Fixture()
    try f.setEnabled(false)
    f.coldStart()
    #expect(HapticsPrefsStore.load(from: f.store).enabled == false)
    f.load()
    #expect(f.enabledSync == false)
}

@Test @MainActor func viewModelStartsFromTheCacheAndLiveUpdatesOnSetEnabled() throws {
    let f = try Fixture()
    let vm = HapticsViewModel(prefs: f.store, dispatcher: f.dispatcher)
    #expect(vm.enabled == true)
    vm.setEnabled(false)
    #expect(vm.enabled == false)
    #expect(f.enabledSync == false)
    try f.setEnabled(true)          // changed from anywhere → the screen follows
    vm.refresh()
    #expect(vm.enabled == true)
}

// MARK: intensity — persisted, clamped [1,100], orthogonal to enabled

@Test @MainActor func intensityDefaultsTo100() throws {
    let f = try Fixture()
    #expect(HapticsPrefsStore.load(from: f.store).intensity == 100)
    #expect(JIHapticsPrefs.defaultIntensity == 100)
}

@Test @MainActor func intensitySyncReadsTheDefaultThenCatchesUp() throws {
    let f = try Fixture()
    try f.setIntensity(42)
    f.coldStart()
    #expect(f.intensitySync == 100)
    f.load()
    #expect(f.intensitySync == 42)
}

@Test @MainActor func setIntensityUpdatesTheSyncCacheImmediately() throws {
    let f = try Fixture()
    try f.setIntensity(30)
    #expect(f.intensitySync == 30)
    #expect(try f.store.get(HapticsPrefsStore.intensityKey, as: Int.self) == 30)
}

@Test @MainActor func intensityRoundTrip42() throws {
    let f = try Fixture()
    try f.setIntensity(42)
    f.coldStart()
    #expect(HapticsPrefsStore.load(from: f.store).intensity == 42)
}

@Test @MainActor func clampsBelowOneUpToOne() throws {
    let f = try Fixture()
    try f.setIntensity(0)
    #expect(f.intensitySync == 1)
    #expect(HapticsPrefsStore.load(from: f.store).intensity == 1)
    try f.setIntensity(-50)
    #expect(f.intensitySync == 1)
}

@Test @MainActor func clampsAbove100DownTo100() throws {
    let f = try Fixture()
    try f.setIntensity(150)
    #expect(f.intensitySync == 100)
    #expect(HapticsPrefsStore.load(from: f.store).intensity == 100)
}

@Test @MainActor func viewModelIntensityLiveUpdates() throws {
    let f = try Fixture()
    let vm = HapticsViewModel(prefs: f.store, dispatcher: f.dispatcher)
    #expect(vm.intensity == 100)
    vm.commit(60)
    #expect(vm.intensity == 60)
    #expect(f.intensitySync == 60)
    #expect(HapticsPrefsStore.load(from: f.store).intensity == 60)
    vm.commit(20)
    #expect(vm.intensity == 20)
}

@Test @MainActor func intensityAndEnabledAreIndependent() throws {
    let f = try Fixture()
    try f.setIntensity(20)
    try f.setEnabled(false)
    #expect(f.intensitySync == 20)
    #expect(f.enabledSync == false)
    try f.setEnabled(true)
    #expect(f.intensitySync == 20)
    #expect(HapticsPrefsStore.load(from: f.store) == JIHapticsPrefs(enabled: true, intensity: 20))
}

// MARK: a corrupt / foreign blob reads as its default, field by field

@Test @MainActor func aCorruptBlobFallsBackPerField() throws {
    let f = try Fixture()
    try f.store.set(HapticsPrefsStore.intensityKey, "not a number")
    try f.store.set(HapticsPrefsStore.enabledKey, false)
    #expect(HapticsPrefsStore.load(from: f.store) == JIHapticsPrefs(enabled: false, intensity: 100))
}

// MARK: the slider's own loop (HapticIntensitySlider.tsx) + "Feel it"

@Test @MainActor func sliderTicksAtDetentCrossingsAndOnceMoreOnRelease() throws {
    let f = try Fixture()
    let vm = HapticsViewModel(prefs: f.store, dispatcher: f.dispatcher)
    vm.dragTo(95); vm.dragTo(91)                 // still bucket 4 (100) — no tick (90 would tie → lower detent)
    #expect(f.fallback.calls.isEmpty)
    vm.dragTo(75)                                // → bucket 3 (80): one tick
    vm.dragTo(65)                                // → bucket 2 (60): one tick
    #expect(f.fallback.calls == [.selection, .selection])
    vm.commit(65)                                // release: persist + one more tick
    #expect(f.fallback.calls.count == 3)
    #expect(HapticsPrefsStore.load(from: f.store).intensity == 65)
}

@Test @MainActor func sliderPersistsSilentlyWhileHapticsAreOff() throws {
    let f = try Fixture()
    let vm = HapticsViewModel(prefs: f.store, dispatcher: f.dispatcher)
    vm.setEnabled(false)
    vm.dragTo(20); vm.commit(20)
    #expect(f.fallback.calls.isEmpty)
    #expect(HapticsPrefsStore.load(from: f.store).intensity == 20)
}

@Test @MainActor func nudgeMovesOneDetentAndClamps() throws {
    let f = try Fixture()
    let vm = HapticsViewModel(prefs: f.store, dispatcher: f.dispatcher)
    vm.nudge(-1); #expect(vm.intensity == 80)
    vm.nudge(+1); vm.nudge(+1); #expect(vm.intensity == 100)
    vm.commit(5); vm.nudge(-1); #expect(vm.intensity == 1)
}

@Test @MainActor func feelItPlaysTheFourMomentVocabularySample() async throws {
    let f = try Fixture()
    let vm = HapticsViewModel(prefs: f.store, dispatcher: f.dispatcher)
    vm.feelIt()
    #expect(f.fallback.calls == [.impact(.light)])
    // The sample is time-scheduled (+100/+200/+500 ms); poll rather than fixed-sleep so a busy
    // main actor (parallel suites) can't starve the last pulse out of the window.
    for _ in 0..<40 where f.fallback.calls.count < 4 { try await Task.sleep(for: .milliseconds(100)) }
    #expect(f.fallback.calls == [.impact(.light), .selection, .impact(.light), .notification(.success)], "got \(f.fallback.calls)")
}

@Test @MainActor func captionMirrorsSettingsTsx() throws {
    let f = try Fixture()
    let vm = HapticsViewModel(prefs: f.store, dispatcher: f.dispatcher)
    #expect(vm.capabilityCaption == "Basic vibration")   // no engine in the test host
    #expect(vm.subtitle == "Vibration feedback on verdicts, PRs, saves, and selections · Basic vibration")
}

// MARK: registry

@Test @MainActor func hapticsSectionIsRegisteredInThePreferencesBand() {
    let ids = SettingsRegistry.sections.map(\.id)
    #expect(ids.contains(HapticsSection.sectionId))
    #expect(Set(ids).count == ids.count)
    let s = SettingsRegistry.sections.first { $0.id == HapticsSection.sectionId }!
    #expect(SettingsGroup(sortKey: s.sortKey) == .preferences)
    #expect(s.sortKey > AppearanceSection().sortKey)   // RN: the Feel card follows Appearance
    #expect(s.title == "Haptics")
}
