import Foundation
import Testing
import JICore
@testable import JIDesign

// W-B53 (B-53). The "changed" gate tier's second pulse is scheduled through an injectable
// `JIHapticGap`: `.wallClock` (the app default, `Task.sleep`) and `.immediate` (tests: the
// closure runs inline, so the two-pulse assertions need no wall time and cannot race).

@Test @MainActor func wallClockGapFiresAfterTheGap() async throws {
    var fired = 0
    JIHapticGap.wallClock.schedule(10) { fired += 1 }
    #expect(fired == 0)   // never inline: the app keeps the real gap
    for _ in 0..<200 where fired == 0 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(fired == 1)
}

@Test @MainActor func immediateGapFiresSynchronously() {
    let r = Rig()
    r.dispatcher.gap = .immediate
    r.dispatcher.fire(.gateChange(.changed))
    #expect(r.fallback.calls == [.impact(.rigid), .impact(.rigid)])
}

@Test @MainActor func theDispatcherDefaultsToTheWallClockGap() {
    let r = Rig()
    r.dispatcher.fire(.gateChange(.changed))
    #expect(r.fallback.calls == [.impact(.rigid)])   // second pulse still pending on wall time
}
