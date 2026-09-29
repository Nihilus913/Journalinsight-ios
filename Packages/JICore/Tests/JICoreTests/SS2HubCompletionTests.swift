import Foundation
import Testing
@testable import JICore

/// W-SSOT-1 SS-2: `GET /training/day/{date}` `completion` — the hub's ONE completion rule
/// (HT `app/training/completion.py`). The JSON below is HT's golden verbatim:
/// `HealthTraining/tests/fixtures/ss2/day_completion_golden.json` (Tue interval day with only a walk,
/// Wed strength+Z2 day with only an Apple strength session, Thu Z2 day with a run).
@Suite struct SS2HubCompletionTests {
    static let golden = """
    {
      "2026-09-29": {"session_type": "interval", "owed": true,
        "parts": [{"part": "cardio", "done": false, "activity_ids": []}], "status": "open", "credited": false},
      "2026-09-30": {"session_type": "strength", "owed": true,
        "parts": [{"part": "strength", "done": true, "activity_ids": [9100002]},
                  {"part": "cardio", "done": false, "activity_ids": []}], "status": "partial", "credited": true},
      "2026-10-01": {"session_type": "z2", "owed": true,
        "parts": [{"part": "cardio", "done": true, "activity_ids": [9100003]}], "status": "done", "credited": true}
    }
    """

    static func decoded() throws -> [String: HubCompletion] {
        try JSON.decoder.decode([String: HubCompletion].self, from: Data(golden.utf8))
    }

    static let t0 = Date(timeIntervalSince1970: 1_790_600_000)
    static func w(_ kind: TodayWorkout.Kind, _ name: String, min: Double = 45, hub: Int? = nil, at offset: Double = 0) -> TodayWorkout {
        TodayWorkout(kind: kind, activityName: name, start: t0.addingTimeInterval(offset),
                     end: t0.addingTimeInterval(offset + min * 60), sourceName: "Garmin", hubActivityId: hub)
    }

    @Test func decodesTheHubGolden() throws {
        let g = try Self.decoded()
        let tue = try #require(g["2026-09-29"]), wed = try #require(g["2026-09-30"]), thu = try #require(g["2026-10-01"])
        #expect(tue.sessionType == "interval" && tue.status == "open" && !tue.credited && tue.owed)
        #expect(wed.isPartial && wed.credited && wed.parts.map(\.part) == ["strength", "cardio"])
        #expect(wed.parts[0].activityIds == [9_100_002])
        #expect(thu.isDone && thu.parts[0].activityIds == [9_100_003])
    }

    @Test func dayDetailCarriesCompletionAndAnOlderHubOmitsIt() throws {
        let with = """
        {"date":"2026-09-30","activities":[],"exercise_sets":[],"planned_session":null,
         "completion":{"session_type":"rest","owed":false,"parts":[],"status":"open","credited":false}}
        """
        let d = try JSON.decoder.decode(TrainingDayDetail.self, from: Data(with.utf8))
        #expect(d.completion?.sessionType == "rest" && d.completion?.owed == false)
        let old = #"{"date":"2026-09-30","activities":[],"exercise_sets":[]}"#
        #expect(try JSON.decoder.decode(TrainingDayDetail.self, from: Data(old.utf8)).completion == nil)
    }

    @Test func walkOnAnIntervalDayStaysOpenEvenUnderALabelThatWouldTakeIt() throws {
        let tue = try #require(Self.decoded()["2026-09-29"])
        let walk = Self.w(.cardio, "Walking", min: 60, hub: 9_100_001)
        // The label rule alone would call a "Long Z2" walk done; the hub's interval rule wins.
        #expect(SessionCompletion.progress(sessionLabel: "Long Z2", workouts: [walk]).isComplete)
        let p = SessionCompletion.progress(sessionLabel: "Long Z2", workouts: [walk], hub: tue)
        #expect(p.parts.map(\.part) == [.intervals])
        #expect(!p.isComplete && !p.anyDone)
        #expect(!SessionCompletion.resolve(planned: .cardio, workouts: [walk], hub: tue).isDone)
    }

    @Test func strengthOnlyOnAStrengthZ2DayIsPartialWithTheHubsWorkout() throws {
        let wed = try #require(Self.decoded()["2026-09-30"])
        let lift = Self.w(.strength, "Traditional strength training", min: 50, hub: 9_100_002)
        let p = SessionCompletion.progress(sessionLabel: nil, workouts: [lift], hub: wed)
        #expect(p.parts.map(\.part) == [.strength, .steadyCardio])
        #expect(p.isPartial && !p.isComplete)
        #expect(p.parts[0].workout == lift)
        #expect(p.completion.isDone)          // the lead part (the lift) — NEXT's "Done ·" line
    }

    @Test func aPhoneOnlyRunFillsAPartTheHubHasOpen() throws {
        let wed = try #require(Self.decoded()["2026-09-30"])
        let lift = Self.w(.strength, "Traditional strength training", min: 50, hub: 9_100_002)
        let run = Self.w(.cardio, "Outdoor Run", min: 35, hub: nil, at: 3600)
        let p = SessionCompletion.progress(sessionLabel: nil, workouts: [lift, run], hub: wed)
        #expect(p.isComplete)
        // …but a hub row the hub already judged never re-opens as done by the app's own rule.
        let hubRun = Self.w(.cardio, "Walking", min: 35, hub: 9_100_009, at: 3600)
        #expect(SessionCompletion.progress(sessionLabel: nil, workouts: [lift, hubRun], hub: wed).isPartial)
    }

    @Test func hubDoneWithoutAWorkoutStillCountsThePart() throws {
        let stepDay = HubCompletion(sessionType: "z2", owed: true,
                                    parts: [.init(part: "cardio", done: true, activityIds: [])], status: "done", credited: true)
        let p = SessionCompletion.progress(sessionLabel: "Long Z2", workouts: [], hub: stepDay)
        #expect(p.isComplete && p.parts[0].workout == nil)
    }

    @Test func noHubCompletionKeepsTheAppRule() {
        let lift = Self.w(.strength, "Strength", min: 50)
        #expect(SessionCompletion.progress(sessionLabel: "Day 1 Full Upper + Z2 40min", workouts: [lift], hub: nil)
                == SessionCompletion.progress(sessionLabel: "Day 1 Full Upper + Z2 40min", workouts: [lift]))
    }
}
