import Foundation
import Testing
@testable import JICore

/// W-B81 A-5: `/training/day/{date}` rows carry the source + HR + load (HT `_ACTIVITY_EXTRA_COLS`),
/// and — when the hub exposes it — iOS 27 time-in-zone. All optional: an older hub omits them.
@Suite struct B81DayActivityTests {
    @Test func decodesAppleRunWithSourceHeartRateAndLoad() throws {
        let json = """
        {"date":"2026-09-28","activities":[
          {"activity_id":900001,"type":"running","name":"Outdoor Run","duration_sec":2412,"distance_m":6020.5,
           "dso_key":4,"avg_hr":151,"max_hr":178,"session_load":241.2,"start_time_utc":"2026-09-28T05:02:04+00:00","source":"apple",
           "zone_time":[{"zone":1,"lower_bpm":0,"upper_bpm":125,"seconds":240},{"zone":5,"lower_bpm":170,"upper_bpm":null,"seconds":60}]}
        ],"exercise_sets":[]}
        """
        let a = try JSON.decoder.decode(TrainingDayDetail.self, from: Data(json.utf8)).activities[0]
        #expect(a.source == "apple")
        #expect(a.isAppleHealth)
        #expect(a.avgHr == 151)
        #expect(a.maxHr == 178)
        #expect(a.sessionLoad == 241.2)
        #expect(a.startTimeUtc == "2026-09-28T05:02:04+00:00")
        #expect(a.zoneTime?.count == 2)
        #expect(a.zoneTime?[1].upperBpm == nil)
        #expect(a.zoneTime?[1].seconds == 60)
    }

    @Test func olderHubRowDecodesWithoutTheNewFields() throws {
        let json = """
        {"activity_id":1,"type":"strength_training","name":"Full Upper","duration_sec":3120,"distance_m":null}
        """
        let a = try JSON.decoder.decode(DayActivity.self, from: Data(json.utf8))
        #expect(a.source == nil)
        #expect(!a.isAppleHealth)
        #expect(a.avgHr == nil)
        #expect(a.zoneTime == nil)
    }

    @Test func startDateParsesTheHubsIsoTimestamp() {
        let a = DayActivity(activityId: 1, type: "running", name: nil, durationSec: 60, distanceM: nil,
                            source: "apple", startTimeUtc: "2026-09-28T05:02:04+00:00")
        #expect(a.startDate == Date(timeIntervalSince1970: 1_790_571_724))
        #expect(DayActivity(activityId: 1, type: "x", name: nil, durationSec: nil, distanceM: nil).startDate == nil)
    }
}
