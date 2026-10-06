#if canImport(HealthKit)
import Foundation
import Testing
import JICore
@testable import JIHealthKit

/// W-FIX-P2 RG-17 (B-112): at most ONE morning verdict banner. The hub's ntfy push wins; the
/// on-device local banner posts only when the hub missed the morning (no hub verdict for the day).
@Suite struct NotifierDedupeTests {
    private func result(_ verdict: String) -> OnDeviceVerdictResult {
        OnDeviceVerdictResult(verdict: verdict, reason: nil, sessionPrescription: nil, signals: [], baselineNights: 28)
    }

    @Test func hubBannerSentSuppressesTheLocalBanner() async {
        let notifier = RecordingNotifier()
        let runner = OnDeviceVerdictRunner(compute: { [result] _ in result("GO — Strength A") },
                                           notifier: notifier, hubSent: { _ in true })
        #expect(await runner.run(day: "2026-10-05") == .suppressedHub)
        #expect(notifier.posts.isEmpty)
    }

    @Test func hubMissedPostsTheLocalBanner() async {
        let notifier = RecordingNotifier()
        let runner = OnDeviceVerdictRunner(compute: { [result] _ in result("GO — Strength A") },
                                           notifier: notifier, hubSent: { _ in false })
        #expect(await runner.run(day: "2026-10-05") == .notified)
        #expect(notifier.posts.count == 1)
    }

    @Test func suppressedMorningStillFeedsTheShadowLog() async {
        let seen = LockedBox(0)
        let runner = OnDeviceVerdictRunner(compute: { [result] _ in result("GO — Strength A") },
                                           notifier: RecordingNotifier(),
                                           onResult: { _, _, _ in seen.value += 1 }, hubSent: { _ in true })
        _ = await runner.run(day: "2026-10-05")
        #expect(seen.value == 1)
    }
}
#endif
