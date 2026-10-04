import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-B31 R-1 (P-haptics / P-session-coach). Port of `mobile/__tests__/haptics/haptics.test.ts`
// L475–520 "SessionCoach — the HR-cap handler fires hapticGateChange on real edges" (4 tests).
// RN re-renders `SessionCoach` with a new `LiveSessionState`; here each reading is one poll tick
// of `SessionCoachViewModel` over a scripted feed. Fires are recorded via the dispatcher's
// `[FEELGATE_HAPTIC]` marker sink (logged exactly once per fire, before any native call), on a
// private `JIHapticDispatcher` per test — never `.shared`.

/// RN `capableState(hr)`: `{ hr_bpm: hr, elapsed_s: 60, load: 100, target_load: 300 }`.
private actor ScriptedFeed: LiveSessionProviding {
    private var hr: Int?
    init(_ hr: Int?) { self.hr = hr }
    func set(_ hr: Int?) { self.hr = hr }
    func liveSession() async throws -> LiveSessionSample {
        LiveSessionSample(hrBpm: hr, elapsedS: 60, load: 100, targetLoad: 300)
    }
}

@MainActor
private final class Rig {
    let feed: ScriptedFeed
    let dispatcher = JIHapticDispatcher(player: nil, fallback: NoopFallback())
    var fired: [String] = []
    let vm: SessionCoachViewModel

    /// Limit 180 (cap 180, Zone 5 not avoided) — the RN fixture's cap.
    init(mountHr: Int?) {
        feed = ScriptedFeed(mountHr)
        dispatcher.player = nil
        vm = SessionCoachViewModel(live: feed, settings: GateSettings(hrCapBpm: 180), haptics: dispatcher)
        dispatcher.marker = { [weak self] line in
            if let label = JIFeelgateMarker.parse(line)?.label { MainActor.assumeIsolated { self?.fired.append(label) } }
        }
    }
    /// One mount / re-render = one poll tick.
    func render() async { await vm.tick() }
    func rerender(_ hr: Int?) async {
        await feed.set(hr)
        await vm.tick()
    }
}

@Suite(.serialized)
@MainActor
struct SessionCoachHapticsTests {
    @Test func mountingAlreadyUnderCapFiresNothing() async {
        let rig = Rig(mountHr: 140)
        await rig.render()
        #expect(rig.fired.isEmpty)
    }

    @Test func mountingAlreadyOverCapFiresTheFailedTierImmediately() async {
        let rig = Rig(mountHr: 190)
        await rig.render()
        #expect(rig.fired == ["gateChange:failed"])
    }

    @Test func crossingUnderApproachingBreachFiresChangedThenFailed() async {
        let rig = Rig(mountHr: 140)
        await rig.render()
        #expect(rig.fired.isEmpty)
        await rig.rerender(165) // -> approaching
        #expect(rig.fired == ["gateChange:changed"])
        await rig.rerender(190) // -> breach
        #expect(rig.fired == ["gateChange:changed", "gateChange:failed"])
    }

    @Test func repeatedReadingsInTheSameBandFireNothingFurther() async {
        let rig = Rig(mountHr: 190)
        await rig.render()
        #expect(rig.fired.count == 1)
        await rig.rerender(192)
        await rig.rerender(195)
        #expect(rig.fired.count == 1)
    }
}
