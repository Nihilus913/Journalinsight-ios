import Testing
import Foundation
@testable import JournalInsight

@Suite("LockPolicy")
struct LockPolicyTests {

    @Test("Default policy is fiveMinutes")
    func defaultPolicy() {
        #expect(LockPolicy.default == .fiveMinutes)
    }

    @Test("All cases produce distinct durations")
    func distinctDurations() {
        let durations = LockPolicy.allCases.map(\.duration)
        let secondsSet = Set(durations.map { $0.components.seconds })
        #expect(secondsSet.count == LockPolicy.allCases.count)
    }

    @Test("Specific duration values")
    func specificDurations() {
        #expect(LockPolicy.immediately.duration  == .seconds(0))
        #expect(LockPolicy.oneMinute.duration    == .seconds(60))
        #expect(LockPolicy.fiveMinutes.duration  == .seconds(300))
        #expect(LockPolicy.fifteenMinutes.duration == .seconds(900))
        #expect(LockPolicy.oneHour.duration      == .seconds(3600))
    }

    @Test("Raw values are stable strings")
    func rawValuesStable() {
        #expect(LockPolicy.immediately.rawValue    == "immediately")
        #expect(LockPolicy.oneMinute.rawValue      == "oneMinute")
        #expect(LockPolicy.fiveMinutes.rawValue    == "fiveMinutes")
        #expect(LockPolicy.fifteenMinutes.rawValue == "fifteenMinutes")
        #expect(LockPolicy.oneHour.rawValue        == "oneHour")
    }

    @Test("Display label is non-empty for all cases")
    func labels() {
        for policy in LockPolicy.allCases {
            #expect(!policy.displayLabel.isEmpty)
        }
    }
}
