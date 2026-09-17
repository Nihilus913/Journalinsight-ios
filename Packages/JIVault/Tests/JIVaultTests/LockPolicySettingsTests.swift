import Foundation
import Testing
@testable import JIVault

@Suite
struct LockPolicySettingsTests {
    private func freshSuite() -> UserDefaults {
        let suite = UserDefaults(suiteName: "JIVaultTests.\(UUID().uuidString)")!
        return suite
    }

    @Test
    func defaultsToFiveMinutesWhenUnset() {
        let settings = LockPolicySettings(suite: freshSuite())
        #expect(settings.current == .fiveMinutes)
    }

    @Test
    func persistsAcrossInstancesSharingSuite() {
        let suite = freshSuite()
        let settings1 = LockPolicySettings(suite: suite)
        settings1.current = .immediately
        let settings2 = LockPolicySettings(suite: suite)
        #expect(settings2.current == .immediately)
    }
}
