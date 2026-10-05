import Foundation
import Testing
import JICore
import JICompute
@testable import JIFeatures

/// W-FIX-P1 RG-08 (B-123): the Decide ring showed "44 Readiness" (/vitals/recovery
/// last_night.readiness, recomputed after the 07:04 sync) next to the "Recovery score 39" row
/// (the gate's signal, 05:08) for the same night. The ring is the call's recovery score now;
/// readiness only when the hub sent no score.
@Suite struct B123RingTests {
    /// The 2026-10-05 05:08 gate signals, trimmed to the recovery row.
    private let signals0508 = [
        GateSignal(key: "recovery", label: "Recovery score", value: 39, unit: "", threshold: 33,
                   direction: .min, status: .pass, note: "Recovery 39"),
        GateSignal(key: "hrv", label: "HRV (7-day)", value: 22, unit: "ms", threshold: 23,
                   direction: .min, status: .amber, note: "HRV 7-day 22 ms — under band 23–27 ms"),
    ]

    @Test func ringIsTheCallsRecoveryScoreNotReadiness() {
        let hub = decideHubRecovery(signals0508)
        #expect(hub == 39)
        let ring = decideRingScore(readiness: 44, recovery: nil, hubRecovery: hub)
        #expect(ring == 39)
        #expect(ring == signals0508.first { $0.label == "Recovery score" }?.value)
        #expect(decideReadinessCaption(score: ring, nights: nil, recovery: nil, hubRecovery: hub) == "Recovery")
    }

    @Test func readinessOnlyWhenTheHubHasNoScore() {
        #expect(decideRingScore(readiness: 44, recovery: nil, hubRecovery: nil) == 44)
        #expect(decideReadinessCaption(score: 44, nights: nil, recovery: nil, hubRecovery: nil) == "Readiness")
    }
}
