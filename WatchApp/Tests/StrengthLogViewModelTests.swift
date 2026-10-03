import Foundation
import Testing
import JICompute
import JIWorkouts
@testable import WatchApp

/// W-B38-B B-4 — the Watch strength screen's rendered strings and the cap colour role. The
/// model's behaviour (prefill, log / edit / delete, timers, Double Tap, Action Button) is
/// covered by `JIWorkoutsTests/StrengthLogViewModelTests` + `SetTimerWatchTests` (swift test).
@MainActor
struct StrengthLogViewModelTests {
    private let session = UUID()

    @Test func setSummaryNeverRendersAZero() {
        let reps = StrengthBridgeSet(clientId: UUID(), sessionClientId: session, exerciseKey: "bench", exerciseId: nil, setIndex: 1,
                                     kind: .reps, reps: 8, weightKg: 62.5, durationS: nil, rpe: nil, performedAt: .now)
        #expect(StrengthSetEntry.summary(reps) == "62.5 kg × 8")
        var bodyweight = reps; bodyweight.weightKg = nil
        #expect(StrengthSetEntry.summary(bodyweight) == "BW × 8")
        let timed = StrengthBridgeSet(clientId: UUID(), sessionClientId: session, exerciseKey: "plank", exerciseId: nil, setIndex: 1,
                                      kind: .timed, reps: nil, weightKg: nil, durationS: 45, rpe: nil, performedAt: .now)
        #expect(StrengthSetEntry.summary(timed) == "45 s")
    }

    @Test func capRoleNeverShowsGreenWithoutAReading() {
        #expect(StrengthCapGauge.role(.unknown) == .muted)
        #expect(StrengthCapGauge.role(.under) == .go)
        #expect(StrengthCapGauge.role(.approaching) == .reduced)
        #expect(StrengthCapGauge.role(.breach) == .danger)
    }

    @Test func timerClockFormatsMinutes() {
        #expect(StrengthTimerCard.clock(125) == "2:05")
        #expect(StrengthTimerCard.clock(0) == "0:00")
    }

    @Test func compositionRegistersWithTheLauncher() {
        let c = StrengthLogComposition()
        #expect(StrengthSessionLauncher.shared.model === c.model)
    }
}
