#if canImport(WorkoutKit)
import Testing
@testable import JIFeatures

struct TrainingHeaderTests {
    @Test func watchLineFollowsTheSendState() {
        #expect(trainingWatchLine(nil) == nil)                          // no WorkoutKit / not wired → no claim
        #expect(trainingWatchLine(.idle) == "Not on your Watch yet")
        #expect(trainingWatchLine(.error("x")) == "Not on your Watch yet")
        #expect(trainingWatchLine(.sending) == "Sending to your Watch…")
        #expect(trainingWatchLine(.sent(2)) == "On your Watch")
    }
}
#endif
