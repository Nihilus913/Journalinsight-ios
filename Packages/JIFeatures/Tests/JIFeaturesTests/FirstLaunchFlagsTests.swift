import Testing
@testable import JIFeatures

// RG-77 (B-43/B-21): first launch — `-start-tab` is not overridden by the gate, and the
// notification permission alert never pops over Decide.
@Suite struct FirstLaunchFlagsTests {
    @Test func startTabWinsOverTheGateUnlessForced() {
        #expect(GateLaunch.yieldsToStartTab(["app", "-start-tab", "training"]))
        #expect(!GateLaunch.yieldsToStartTab(["app", "-start-tab", "training", "-JIForceGate", "YES"]))
        #expect(!GateLaunch.yieldsToStartTab(["app"]))
    }

    @Test func undecidedPermissionWaitsWhileDecideIsUp() {
        #expect(!GateLaunch.shouldAskNotificationsAtLaunch(undecided: true, gateOpens: true))
        #expect(GateLaunch.shouldAskNotificationsAtLaunch(undecided: true, gateOpens: false))
        #expect(GateLaunch.shouldAskNotificationsAtLaunch(undecided: false, gateOpens: true))
    }
}
