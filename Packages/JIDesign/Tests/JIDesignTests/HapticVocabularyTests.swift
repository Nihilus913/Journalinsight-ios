import Foundation
import os
import Testing
import JICore
@testable import JIDesign

// W8-L1 (P-haptics). Port of `mobile/__tests__/haptics/haptics.test.ts` (36 of 40 — the 4
// `SessionCoach` handler cases need the Session Coach call site, out of this lane) onto
// `JIHapticDispatcher` with a recording engine (`playHaptic` spy) and a recording fallback
// (the expo-haptics spies). `@MainActor`: the dispatcher is main-actor (UIKit generators).

@MainActor
final class RecordingPlayer: JIHapticPlayer {
    var capabilities: JIHapticCapabilities?
    var result: JIHapticFireResult = JIHapticFireResult(fired: true, path: .composition)
    var throwOnPlay = false
    var calls: [(JIHapticRecipeName, Double)] = []
    struct Crash: Error {}
    init(capabilities: JIHapticCapabilities? = nil) { self.capabilities = capabilities }
    func play(_ recipe: JIHapticRecipe, scale: Double) throws -> JIHapticFireResult {
        calls.append((recipe.name, scale))
        if throwOnPlay { throw Crash() }
        return result
    }
}

@MainActor
final class RecordingFallback: JIHapticFallbackPlayer {
    var calls: [JIHapticFallback] = []
    func play(_ fallback: JIHapticFallback) { calls.append(fallback) }
}

/// RN `jest.spyOn(console, "log")` — captures marker lines.
final class MarkerLog: Sendable {
    private let lock = OSAllocatedUnfairLock<[String]>(initialState: [])
    var lines: [String] { lock.withLock { $0 } }
    var last: String? { lines.last }
    var sink: JIFeelgateMarker.Sink { { line in self.lock.withLock { $0.append(line) } } }
}

@MainActor
struct Rig {
    let player = RecordingPlayer()
    let fallback = RecordingFallback()
    let dispatcher: JIHapticDispatcher
    init(engine: Bool = false) {
        dispatcher = JIHapticDispatcher(player: player, fallback: fallback)
        if engine { player.capabilities = Rig.rich }
        dispatcher.marker = { _ in }
    }
    static let rich = JIHapticCapabilities(hasVibrator: true, hasAmplitudeControl: true, primitivesSupported: [], apiLevel: 34)
    func setEnabled(_ on: Bool) { dispatcher.prefs.enabled = on }
    func setIntensity(_ pct: Int) { dispatcher.prefs.intensity = JIHapticsPrefs.clampIntensity(Double(pct)) }
}

// MARK: hapticVerdictReveal — the notification family

@Test @MainActor func verdictRevealGoFiresSuccess() {
    let r = Rig(); r.dispatcher.fire(.verdictReveal(.go))
    #expect(r.fallback.calls == [.notification(.success)])
}
@Test @MainActor func verdictRevealAmberFiresWarning() {
    let r = Rig(); r.dispatcher.fire(.verdictReveal(.amber))
    #expect(r.fallback.calls == [.notification(.warning)])
}
@Test @MainActor func verdictRevealRedFiresError() {
    let r = Rig(); r.dispatcher.fire(.verdictReveal(.red))
    #expect(r.fallback.calls == [.notification(.error)])
}
@Test @MainActor func verdictRevealMutedFiresNothing() {
    let r = Rig(); r.dispatcher.fire(.verdictReveal(.muted))
    #expect(r.fallback.calls.isEmpty)
}

@Test @MainActor func goalHitFiresHeavyImpact() {
    let r = Rig(); r.dispatcher.fire(.goalHit)
    #expect(r.fallback.calls == [.impact(.heavy)])
}
@Test @MainActor func saveSuccessFiresLightImpact() {
    let r = Rig(); r.dispatcher.fire(.saveSuccess)
    #expect(r.fallback.calls == [.impact(.light)])
}
@Test @MainActor func selectionFiresSelectionOnce() {
    let r = Rig(); r.dispatcher.fire(.selection)
    #expect(r.fallback.calls == [.selection])
}

// MARK: the Settings disable toggle gates every family

@Test @MainActor func disabledFiresNothingAtAll() {
    let r = Rig(); r.setEnabled(false)
    r.dispatcher.fire(.verdictReveal(.go)); r.dispatcher.fire(.goalHit); r.dispatcher.fire(.saveSuccess); r.dispatcher.fire(.selection)
    #expect(r.fallback.calls.isEmpty)
    #expect(r.player.calls.isEmpty)
}
@Test @MainActor func resumesFiringOnceSwitchedBackOn() {
    let r = Rig(); r.setEnabled(false); r.setEnabled(true)
    r.dispatcher.fire(.selection)
    #expect(r.fallback.calls == [.selection])
}

@Test @MainActor func aThrowingEngineCallIsSwallowedNeverThrown() {
    let r = Rig(engine: true); r.player.throwOnPlay = true
    r.dispatcher.fire(.selection)   // would be `expect(() => …).not.toThrow()`; a throw here fails the test
    #expect(r.fallback.calls == [.selection])
}

// MARK: hapticDragDrop — E18-3

@Test @MainActor func dragDropFiresItsOwnDistinctPulse() {
    let r = Rig(); r.dispatcher.fire(.dragDrop)
    #expect(r.fallback.calls == [.impact(.medium)])
    #expect(JIHapticRecipes.recipe(.dragDrop).fallback != JIHapticRecipes.recipe(.selection).fallback)
}
@Test @MainActor func dragDropRespectsTheToggle() {
    let r = Rig(); r.setEnabled(false); r.dispatcher.fire(.dragDrop)
    #expect(r.fallback.calls.isEmpty)
}
@Test @MainActor func dragDropSwallowsARejectedEngineCall() {
    let r = Rig(engine: true); r.player.throwOnPlay = true
    r.dispatcher.fire(.dragDrop)
    #expect(r.fallback.calls == [.impact(.medium)])
}

// MARK: hapticGateChange — the three escalating tiers

@Test @MainActor func routineFiresOneSoftPulse() {
    let r = Rig(); r.dispatcher.fire(.gateChange(.routine))
    #expect(r.fallback.calls == [.impact(.soft)])
}
@Test @MainActor func failedFiresOneRejectPulseDifferentFromRoutine() {
    let r = Rig(); r.dispatcher.fire(.gateChange(.failed))
    #expect(r.fallback.calls.count == 1)
    #expect(r.fallback.calls != [.impact(.soft)])
}
@Test @MainActor func changedFiresAGenuineTwoPulsePattern() async throws {
    let r = Rig(); r.dispatcher.fire(.gateChange(.changed))
    try await Task.sleep(for: .milliseconds(250))
    #expect(r.fallback.calls == [.impact(.rigid), .impact(.rigid)])
}
@Test @MainActor func theThreeTiersUsePairwiseDistinctShapes() async throws {
    let routine = Rig(); routine.dispatcher.fire(.gateChange(.routine))
    let failed = Rig(); failed.dispatcher.fire(.gateChange(.failed))
    let changed = Rig(); changed.dispatcher.fire(.gateChange(.changed))
    try await Task.sleep(for: .milliseconds(250))
    #expect(routine.fallback.calls.last != failed.fallback.calls.last)
    #expect(changed.fallback.calls.count == 2)
    // Core Haptics side too: three distinct patterns.
    let p = { (t: JIGateChangeTier) in JIHapticRecipes.recipe(t.recipeName).pulses }
    #expect(p(.routine) != p(.changed) && p(.changed) != p(.failed) && p(.routine) != p(.failed))
}
@Test @MainActor func gateChangeRespectsTheToggleForAllThreeTiers() async throws {
    let r = Rig(); r.setEnabled(false)
    r.dispatcher.fire(.gateChange(.routine)); r.dispatcher.fire(.gateChange(.changed)); r.dispatcher.fire(.gateChange(.failed))
    try await Task.sleep(for: .milliseconds(250))
    #expect(r.fallback.calls.isEmpty)
}

// MARK: gateChangeTierFromTones — pure classification (nonisolated: pure)

@Test func aRedVerdictIsAlwaysFailed() {
    #expect(JIHapticRecipes.gateChangeTier(prevTone: .go, nextTone: .red) == .failed)
    #expect(JIHapticRecipes.gateChangeTier(prevTone: .amber, nextTone: .red) == .failed)
    #expect(JIHapticRecipes.gateChangeTier(prevTone: .red, nextTone: .red) == .failed)
}
@Test func theSameToneAsBeforeIsRoutine() {
    #expect(JIHapticRecipes.gateChangeTier(prevTone: .go, nextTone: .go) == .routine)
    #expect(JIHapticRecipes.gateChangeTier(prevTone: .amber, nextTone: .amber) == .routine)
}
@Test func theVeryFirstVerdictIsRoutineNotChanged() {
    #expect(JIHapticRecipes.gateChangeTier(prevTone: nil, nextTone: .go) == .routine)
}
@Test func aGenuineToneFlipThatIsNotRedIsChanged() {
    #expect(JIHapticRecipes.gateChangeTier(prevTone: .amber, nextTone: .go) == .changed)
    #expect(JIHapticRecipes.gateChangeTier(prevTone: .go, nextTone: .amber) == .changed)
}

// MARK: E24-3 — the enabled/intensity gate and engine-vs-fallback dispatch

@Test @MainActor func disabledMeansNoMarkerNoEngineNoFallback() {
    let r = Rig(engine: true); r.setEnabled(false)
    let markers = MarkerLog(); r.dispatcher.marker = markers.sink
    r.dispatcher.fire(.pressIn)
    #expect(markers.lines.isEmpty)
    #expect(r.player.calls.isEmpty)
    #expect(r.fallback.calls.isEmpty)
}
@Test @MainActor func noEngineTakesTheFallbackSynchronouslyWithoutCallingPlay() {
    let r = Rig()
    #expect(r.player.capabilities == nil)
    r.dispatcher.fire(.selection)
    // No await above this line — the fallback fired SYNCHRONOUSLY.
    #expect(r.fallback.calls == [.selection])
    #expect(r.player.calls.isEmpty)
}
@Test @MainActor func engineFiredTrueMeansTheFallbackIsNeverAlsoCalled() {
    let r = Rig(engine: true)
    r.dispatcher.fire(.pressIn)
    #expect(r.player.calls.map(\.0) == [.pressIn])
    #expect(r.fallback.calls.isEmpty)
}
@Test @MainActor func engineDecliningEverythingStillRunsTheFallback() {
    let r = Rig(engine: true); r.player.result = .declined
    r.dispatcher.fire(.selection)
    #expect(r.fallback.calls == [.selection])
}
@Test @MainActor func engineThrowingStillRunsTheFallbackAndNothingThrows() {
    let r = Rig(engine: true); r.player.throwOnPlay = true
    r.dispatcher.fire(.saveSuccess)
    #expect(r.fallback.calls == [.impact(.light)])
}
@Test @MainActor func intensityFeedsScaleThroughTheStevensCurveNotALinearMap() {
    let r = Rig(engine: true); r.setIntensity(60)
    r.dispatcher.fire(.pressIn)
    let (name, scale) = r.player.calls[0]
    #expect(name == .pressIn)
    #expect(abs(scale - pow(0.6, 1.7)) < 1e-6)
    #expect(abs(scale - 0.6) > 0.01)
}
@Test @MainActor func defaultIntensityResolvesToScaleExactlyOne() {
    let r = Rig(engine: true)
    r.dispatcher.fire(.saveSuccess)
    #expect(r.player.calls[0].1 == 1)
}
@Test @MainActor func intensityCanNeverReachZero() {
    let r = Rig(engine: true); r.setIntensity(0)   // clamps to 1
    r.dispatcher.fire(.pressIn)
    let scale = r.player.calls[0].1
    #expect(scale > 0)
    #expect(abs(scale - pow(0.01, 1.7)) < 1e-8)
}
@Test @MainActor func theElevenVocabularyMomentsMapOntoElevenDistinctRecipes() {
    let r = Rig(engine: true)
    r.dispatcher.fire(.pressIn); r.dispatcher.fire(.selection); r.dispatcher.fire(.saveSuccess); r.dispatcher.fire(.goalHit)
    r.dispatcher.fire(.verdictReveal(.go)); r.dispatcher.fire(.verdictReveal(.amber)); r.dispatcher.fire(.verdictReveal(.red))
    r.dispatcher.fire(.dragDrop)
    r.dispatcher.fire(.gateChange(.routine)); r.dispatcher.fire(.gateChange(.changed)); r.dispatcher.fire(.gateChange(.failed))
    let names = r.player.calls.map(\.0.rawValue)
    #expect(Set(names).count == 11)
    #expect(names.sorted() == [
        "pressIn", "selection", "saveSuccess", "goalHit",
        "verdictReveal:go", "verdictReveal:amber", "verdictReveal:red",
        "dragDrop", "gateChange:routine", "gateChange:changed", "gateChange:failed",
    ].sorted())
}
@Test @MainActor func verdictRevealMutedMapsToNoRecipeAtAll() {
    let r = Rig(engine: true)
    r.dispatcher.fire(.verdictReveal(.muted))
    #expect(r.player.calls.isEmpty)
    #expect(JIHapticCue.verdictReveal(.muted).recipeName == nil)
}

// MARK: gateChangeTierFromHrCap — pure classification

@Test func noEdgeIsNil() {
    #expect(JIHapticRecipes.gateChangeTier(prevCap: .under, nextCap: .under) == nil)
    #expect(JIHapticRecipes.gateChangeTier(prevCap: .breach, nextCap: .breach) == nil)
}
@Test func breachingTheCapIsAlwaysFailedEvenFromANilOrUnknownBaseline() {
    #expect(JIHapticRecipes.gateChangeTier(prevCap: .approaching, nextCap: .breach) == .failed)
    #expect(JIHapticRecipes.gateChangeTier(prevCap: nil, nextCap: .breach) == .failed)
    #expect(JIHapticRecipes.gateChangeTier(prevCap: .unknown, nextCap: .breach) == .failed)
}
@Test func arrivingAtOrLeavingUnknownIsNeverHapticWorthy() {
    #expect(JIHapticRecipes.gateChangeTier(prevCap: nil, nextCap: .under) == nil)
    #expect(JIHapticRecipes.gateChangeTier(prevCap: .unknown, nextCap: .under) == nil)
    #expect(JIHapticRecipes.gateChangeTier(prevCap: .under, nextCap: .unknown) == nil)
}
@Test func aRealTransitionOrRecoveringOutOfBreachIsChanged() {
    #expect(JIHapticRecipes.gateChangeTier(prevCap: .under, nextCap: .approaching) == .changed)
    #expect(JIHapticRecipes.gateChangeTier(prevCap: .approaching, nextCap: .under) == .changed)
    #expect(JIHapticRecipes.gateChangeTier(prevCap: .breach, nextCap: .approaching) == .changed)
}

// MARK: verdict reveal dedupe (`verdictRevealed`)

@Test func verdictRevealedIsANewDayNotASameDayRefetch() {
    #expect(JIHapticRecipes.verdictRevealed(prevDate: nil, hadPrev: false, nextDate: "2026-09-18", nextTone: .go))
    #expect(!JIHapticRecipes.verdictRevealed(prevDate: "2026-09-18", hadPrev: true, nextDate: "2026-09-18", nextTone: .go))
    #expect(JIHapticRecipes.verdictRevealed(prevDate: "2026-09-17", hadPrev: true, nextDate: "2026-09-18", nextTone: .amber))
    #expect(!JIHapticRecipes.verdictRevealed(prevDate: "2026-09-17", hadPrev: true, nextDate: "2026-09-18", nextTone: .muted))
    #expect(!JIHapticRecipes.verdictRevealed(prevDate: nil, hadPrev: false, nextDate: nil, nextTone: .go))
}
@Test @MainActor func fireVerdictRevealFiresOncePerDistinctKey() {
    let r = Rig()
    r.dispatcher.fireVerdictReveal(.go, key: "GO|Full upper")
    r.dispatcher.fireVerdictReveal(.go, key: "GO|Full upper")   // tab return, same verdict — silent
    #expect(r.fallback.calls == [.notification(.success)])
    r.dispatcher.fireVerdictReveal(.amber, key: "REDUCE|Easy")   // a new verdict — fires
    #expect(r.fallback.calls == [.notification(.success), .notification(.warning)])
    r.dispatcher.resetForTests()
    r.dispatcher.fireVerdictReveal(.go, key: "GO|Full upper")
    #expect(r.fallback.calls.count == 3)
}

// MARK: recipe table + ladder + prefs values

@Test func everyRecipeNameHasARowWhoseLabelIsItsOwnKey() {
    #expect(JIHapticRecipeName.allCases.count == 11)
    for name in JIHapticRecipeName.allCases {
        let r = JIHapticRecipes.recipe(name)
        #expect(r.label == name.rawValue)
        #expect(!r.pulses.isEmpty)
    }
}
@Test func redRevealAndFailedShareOneRecipeShapeByDesign() {
    #expect(JIHapticRecipes.recipe(.verdictRevealRed).pulses == JIHapticRecipes.recipe(.gateChangeFailed).pulses)
    #expect(JIHapticRecipes.recipe(.saveSuccess).fallback == JIHapticRecipes.recipe(.pressIn).fallback)   // the E18-3 finding
    #expect(JIHapticRecipes.recipe(.saveSuccess).pulses != JIHapticRecipes.recipe(.pressIn).pulses)      // they diverge above that rung
}
@Test func changedIsOneAtomicPatternWithTheDoublePulseGap() {
    let p = JIHapticRecipes.recipe(.gateChangeChanged).pulses
    #expect(p.count == 2)
    #expect(p[1].atMs - p[0].atMs == jiHapticDoublePulseGapMs)
    #expect(JIHapticRecipes.recipe(.gateChangeChanged).fallback == .double(.impact(.rigid), gapMs: 110))
}
@Test func rungTableIosReading() {
    let recipe = JIHapticRecipes.recipe(.pressIn)
    #expect(JIHapticCapabilities(hasVibrator: false, hasAmplitudeControl: false, primitivesSupported: [], apiLevel: 34).rung(for: recipe) == .fallback)
    #expect(JIHapticCapabilities(hasVibrator: true, hasAmplitudeControl: true, primitivesSupported: [], apiLevel: 34).rung(for: recipe) == .composition)
    #expect(JIHapticCapabilities(hasVibrator: true, hasAmplitudeControl: false, primitivesSupported: ["TICK"], apiLevel: 31).rung(for: recipe) == .composition)
    #expect(JIHapticCapabilities(hasVibrator: true, hasAmplitudeControl: false, primitivesSupported: [], apiLevel: 27).rung(for: recipe) == .predefined)
    #expect(JIHapticPath(normalizing: "bogus") == .fallback)
    #expect(JIHapticPath(normalizing: "oneshot") == .oneshot)
    #expect(JIHapticPath(normalizing: nil) == .fallback)
}
@Test func capabilityCaptionMatchesSettingsTsx() {
    #expect(JIHapticCapabilities.caption(nil) == "Basic vibration")
    #expect(JIHapticCapabilities.caption(JIHapticCapabilities(hasVibrator: false, hasAmplitudeControl: false, primitivesSupported: [], apiLevel: 30)) == "No vibrator")
    #expect(JIHapticCapabilities.caption(JIHapticCapabilities(hasVibrator: true, hasAmplitudeControl: true, primitivesSupported: [], apiLevel: 34)) == "Rich haptics")
    #expect(JIHapticCapabilities.caption(JIHapticCapabilities(hasVibrator: true, hasAmplitudeControl: false, primitivesSupported: ["TICK"], apiLevel: 31)) == "Rich haptics")
    #expect(JIHapticCapabilities.caption(JIHapticCapabilities(hasVibrator: true, hasAmplitudeControl: false, primitivesSupported: [], apiLevel: 27)) == "Basic vibration")
}
@Test func intensityCurveAndScaledIntensity() {
    #expect(JIHapticLadder.intensityScale(pct: 100) == 1)
    #expect(abs(JIHapticLadder.intensityScale(pct: 60) - pow(0.6, 1.7)) < 1e-9)
    #expect(JIHapticLadder.scaledIntensity(0.8, scale: 2) == 1)
    #expect(JIHapticLadder.scaledIntensity(0.5, scale: 0.5) == 0.25)
}
@Test func sliderDomainHelpers() {
    #expect(JIHapticIntensity.clampPct(.nan) == 1)
    #expect(JIHapticIntensity.clampPct(-3) == 1)
    #expect(JIHapticIntensity.clampPct(150) == 100)
    #expect(JIHapticIntensity.clampPct(49.5) == 50)
    #expect(JIHapticIntensity.detentBucket(forPct: 1) == 0)
    #expect(JIHapticIntensity.detentBucket(forPct: 30) == 0)   // tie → lower detent
    #expect(JIHapticIntensity.detentBucket(forPct: 31) == 1)
    #expect(JIHapticIntensity.detentBucket(forPct: 100) == 4)
    #expect(JIHapticIntensity.pct(fromOffsetX: 50, trackWidth: 0) == 1)
    #expect(JIHapticIntensity.pct(fromOffsetX: 50, trackWidth: 100) == 50)
    #expect(JIHapticIntensity.pct(fromOffsetX: 200, trackWidth: 100) == 100)
}
@Test func prefsValuesKeysAndClamp() throws {
    #expect(JIHapticsPrefs.enabledKey == "haptics.enabled.v1")
    #expect(JIHapticsPrefs.intensityKey == "haptics.intensity.v1")
    #expect(JIHapticsPrefs.default == JIHapticsPrefs(enabled: true, intensity: 100))
    #expect(JIHapticsPrefs.clampIntensity(0) == 1)
    #expect(JIHapticsPrefs.clampIntensity(-50) == 1)
    #expect(JIHapticsPrefs.clampIntensity(150) == 100)
    #expect(JIHapticsPrefs.clampIntensity(.nan) == 100)   // corrupt blob reads as untouched
    #expect(JIHapticsPrefs.reconcile(enabled: nil, intensity: 42) == JIHapticsPrefs(enabled: true, intensity: 42))
    #expect(JIHapticsPrefs.reconcile(enabled: false, intensity: nil) == JIHapticsPrefs(enabled: false, intensity: 100))
    let blob = try JSON.encoder.encode(JIHapticsPrefs(enabled: false, intensity: 7))
    #expect(try JSON.decoder.decode(JIHapticsPrefs.self, from: blob) == JIHapticsPrefs(enabled: false, intensity: 7))
}
