import Testing
@testable import JIVault

@Suite
struct LockPolicyTests {
    @Test
    func defaultIsFiveMinutes() {
        #expect(LockPolicy.default == .fiveMinutes)
    }

    @Test(arguments: [
        (LockPolicy.immediately, 0),
        (.oneMinute, 60),
        (.fiveMinutes, 300),
        (.fifteenMinutes, 900),
        (.oneHour, 3600),
    ])
    func durationsMatchSpec(policy: LockPolicy, seconds: Int) {
        #expect(policy.duration == .seconds(seconds))
    }

    @Test
    func allCasesHaveDisplayLabels() {
        for policy in LockPolicy.allCases {
            #expect(!policy.displayLabel.isEmpty)
        }
    }
}
