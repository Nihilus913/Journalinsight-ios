import Testing
@testable import JournalInsight

/// W-BUG1 BUG1-6 (RG-77): `-no-healthkit` never reaches a HealthKit authorization request —
/// the cold-start uploader request, the permission model's request and the on-device verdict
/// compute path (whose HealthKit reads would otherwise run) all go through one gate.
@MainActor
@Suite struct NoHealthKitLaunchGateTests {
    final class Counter { var calls = 0 }

    @Test func flagBlocksEveryAuthorizationRequest() async {
        let counter = Counter()
        let ran = await HealthKitLaunchGate.requestIfAllowed(arguments: ["JournalInsight", "-no-healthkit"]) { counter.calls += 1 }
        #expect(ran == false)
        #expect(counter.calls == 0)
        #expect(HealthKitLaunchGate.allowsHealthKit(arguments: ["JournalInsight", "-no-healthkit", "-no-push"]) == false)
    }

    @Test func withoutFlagTheRequestRuns() async {
        let counter = Counter()
        let ran = await HealthKitLaunchGate.requestIfAllowed(arguments: ["JournalInsight"]) { counter.calls += 1 }
        #expect(ran == true)
        #expect(counter.calls == 1)
    }

    @Test func onDeviceComputePathIsOffUnderFlag() {
        #expect(OnDeviceVerdictWiring.healthKitAllowed(arguments: ["JournalInsight", "-no-healthkit"]) == false)
        #expect(OnDeviceVerdictWiring.healthKitAllowed(arguments: ["JournalInsight"]) == true)
    }
}
