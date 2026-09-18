import Foundation
import Testing
import JICore
@testable import JIDesign

// W8-L1 (P-haptics). Port of `mobile/__tests__/haptics/hapticsFeelgateMarker.test.ts` (11): every
// haptic fire emits ONE `[FEELGATE_HAPTIC] <label> t=<epoch ms>` line, correct label, before the
// native call, independent of its outcome, gated by the same master toggle.


@MainActor
private func rig(enabled: Bool = true, engine: Bool = false) -> (Rig, MarkerLog) {
    let r = Rig(engine: engine)
    let log = MarkerLog()
    r.dispatcher.marker = log.sink
    r.dispatcher.nowMs = { 1_758_200_000_123 }
    r.setEnabled(enabled)
    return (r, log)
}

private func expectMarker(_ line: String?, _ label: String) {
    #expect(line?.wholeMatch(of: /^\[FEELGATE_HAPTIC\] (\S+) t=(\d+)$/) != nil, "not a marker: \(line ?? "nil")")
    #expect(line == "[FEELGATE_HAPTIC] \(label) t=1758200000123")
}

@Test @MainActor func markerPressIn() {
    let (r, log) = rig(); r.dispatcher.fire(.pressIn); expectMarker(log.last, "pressIn")
}
@Test @MainActor func markerSaveSuccess() {
    let (r, log) = rig(); r.dispatcher.fire(.saveSuccess); expectMarker(log.last, "saveSuccess")
}
@Test @MainActor func markerGoalHit() {
    let (r, log) = rig(); r.dispatcher.fire(.goalHit); expectMarker(log.last, "goalHit")
}
@Test @MainActor func markerSelection() {
    let (r, log) = rig(); r.dispatcher.fire(.selection); expectMarker(log.last, "selection")
}
@Test @MainActor func markerDragDrop() {
    let (r, log) = rig(); r.dispatcher.fire(.dragDrop); expectMarker(log.last, "dragDrop")
}
@Test @MainActor func markerVerdictRevealLabelsEachToneDistinctly() {
    let (r, log) = rig()
    r.dispatcher.fire(.verdictReveal(.go)); expectMarker(log.last, "verdictReveal:go")
    r.dispatcher.fire(.verdictReveal(.amber)); expectMarker(log.last, "verdictReveal:amber")
    r.dispatcher.fire(.verdictReveal(.red)); expectMarker(log.last, "verdictReveal:red")
}
@Test @MainActor func markerVerdictRevealMutedFiresNoMarker() {
    let (r, log) = rig(); r.dispatcher.fire(.verdictReveal(.muted))
    #expect(log.lines.isEmpty)
}
@Test @MainActor func markerGateChangeLabelsEachTierAndChangedLogsOnceNotTwice() async throws {
    let (r, log) = rig()
    r.dispatcher.fire(.gateChange(.routine)); expectMarker(log.last, "gateChange:routine")
    r.dispatcher.fire(.gateChange(.failed)); expectMarker(log.last, "gateChange:failed")
    let before = log.lines.count
    r.dispatcher.fire(.gateChange(.changed))
    #expect(log.lines.count == before + 1)   // exactly one new line immediately, not one per pulse
    expectMarker(log.last, "gateChange:changed")
    try await Task.sleep(for: .milliseconds(250))
    #expect(log.lines.count == before + 1)   // still just the one after both pulses complete
    #expect(r.fallback.calls.count == 4)     // routine + failed + the two "changed" pulses
}

// the marker respects the same Settings haptics toggle as the native call

@Test @MainActor func noMarkerAtAllWhenHapticsAreDisabled() {
    let (r, log) = rig(enabled: false)
    r.dispatcher.fire(.pressIn); r.dispatcher.fire(.saveSuccess); r.dispatcher.fire(.goalHit); r.dispatcher.fire(.selection)
    r.dispatcher.fire(.dragDrop); r.dispatcher.fire(.verdictReveal(.go)); r.dispatcher.fire(.gateChange(.routine))
    #expect(log.lines.isEmpty)
}
@Test @MainActor func resumesMarkingOnceSwitchedBackOn() {
    let (r, log) = rig(enabled: false); r.setEnabled(true)
    r.dispatcher.fire(.pressIn); expectMarker(log.last, "pressIn")
}
@Test @MainActor func aRejectedNativeCallStillLeavesTheMarkerLogged() {
    let (r, log) = rig(engine: true); r.player.throwOnPlay = true
    r.dispatcher.fire(.pressIn)
    expectMarker(log.last, "pressIn")
    #expect(r.fallback.calls == [.impact(.light)])
}

// the frozen format itself

@Test func markerLineIsByteExactAndRoundTrips() {
    let line = JIFeelgateMarker.line(label: "verdictReveal:go", timestampMs: 1_700_000_000_000)
    #expect(line == "[FEELGATE_HAPTIC] verdictReveal:go t=1700000000000")
    let parsed = JIFeelgateMarker.parse(line)
    #expect(parsed?.label == "verdictReveal:go")
    #expect(parsed?.timestampMs == 1_700_000_000_000)
    #expect(JIFeelgateMarker.parse("[JI_HAPTICS] pressIn") == nil)
    #expect(JIFeelgateMarker.parse("[FEELGATE_HAPTIC] pressIn t=abc") == nil)
    #expect(JIFeelgateMarker.nowMs() > 1_700_000_000_000)
}
