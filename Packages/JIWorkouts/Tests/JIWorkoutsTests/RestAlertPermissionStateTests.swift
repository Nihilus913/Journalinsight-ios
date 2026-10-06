import Foundation
import Testing
@testable import JIWorkouts

// RG-76 (B-43): the watch logger keeps the rest-alert permission answer as a visible state.
@MainActor @Suite struct RestAlertPermissionStateTests {
    @Test func deniedShowsNotificationsOff() async {
        let h = StrengthLogHarness()
        #expect(!h.vm.restAlertsOff)
        await h.vm.requestRestAlertPermission { false }
        #expect(h.vm.restAlertsOff)
        #expect(RestEndAlert.offNotice.hasPrefix("Notifications off"))
    }

    @Test func grantedLeavesItOn() async {
        let h = StrengthLogHarness()
        await h.vm.requestRestAlertPermission { true }
        #expect(!h.vm.restAlertsOff)
    }
}
