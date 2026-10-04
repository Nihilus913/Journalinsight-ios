import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-FIX13 F-8 (B-71) — the gate arcs ("What drove it") stay visible after Go / Adjust: once the
/// call is answered (Coach, Day) the Day shows the same arcs Decide showed.
@MainActor @Suite struct Fix13L3ArcsTests {
    func signals() async throws -> [GateSignal] {
        [GateSignal(key: "hrv", label: "HRV", value: 25, unit: "ms", threshold: 27, direction: .min, status: .amber, note: nil),
         GateSignal(key: "rhr", label: "RHR", value: 58, unit: "bpm", threshold: 65, direction: .max, status: .pass, note: nil),
         GateSignal(key: "recovery", label: "Recovery", value: 72, unit: "", threshold: 50, direction: .min, status: .pass, note: nil)]
    }

    @Test func answeredStatesStillRenderTheArcs() async throws {
        let all = try await signals()
        let decideArcs = RecoveryScoreCard.visibleSignals(all)
        #expect(decideArcs.map(\.key) == ["hrv", "rhr"])
        for answered in [TodayMorningState.coach, .day] {
            #expect(dayGateArcSignals(morningState: answered, gateSignals: all) == decideArcs)
        }
    }

    @Test func decideShowsItsOwnArcsSoTheDayAddsNone() async throws {
        #expect(dayGateArcSignals(morningState: .decide, gateSignals: try await signals()) == nil)
    }

    @Test func noSignalsNoSection() {
        #expect(dayGateArcSignals(morningState: .day, gateSignals: nil) == nil)
        #expect(dayGateArcSignals(morningState: .day, gateSignals: []) == nil)
    }
}
