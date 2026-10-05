import Foundation
import Testing
@testable import JICompute

/// B-90 p3 — JICompute MuscleLoad equals the hub oracle (HT `app/training/muscle_load.py`) on the
/// shared fixture HT `tests/fixtures/muscle_load.json` (byte copy in Resources/golden; regenerate
/// in HT with `tests/muscle_load_cases.py`, never edit here), plus unit cases for the maths.
@Suite struct MuscleLoadTests {
    struct Case: Decodable { let inputs: MuscleLoad.Inputs; let expected: MuscleLoad.Output }

    func fixture() throws -> [String: Case] {
        let url = try #require(Bundle.module.url(forResource: "muscle_load", withExtension: "json", subdirectory: "Resources/golden"))
        return try JSONDecoder().decode([String: Case].self, from: Data(contentsOf: url))
    }

    func rawFixture() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "muscle_load", withExtension: "json", subdirectory: "Resources/golden"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // MARK: parity vs the Python oracle

    @Test func fixtureHasTheOracleCases() throws {
        #expect(Set(try fixture().keys) == ["mixed", "dedupe", "short_history"])
    }

    @Test(arguments: ["mixed", "dedupe", "short_history"])
    func paritySwiftEqualsPython(_ name: String) throws {
        let c = try #require(try fixture()[name])
        let out = try #require(MuscleLoad.compute(c.inputs))
        #expect(out.asOf == c.expected.asOf)
        #expect(out.method == c.expected.method)
        #expect(out.skipped == c.expected.skipped)
        #expect(out.dedupedGarminActivities == c.expected.dedupedGarminActivities)
        #expect(out.muscles.map(\.muscle) == c.expected.muscles.map(\.muscle))
        for (a, b) in zip(out.muscles, c.expected.muscles) { #expect(a == b, "\(name)/\(b.muscle)") }
        #expect(out == c.expected)
    }

    /// The encoded Swift output is key-for-key the oracle's JSON (nulls included), so the hub route
    /// and the device produce one payload shape.
    @Test(arguments: ["mixed", "dedupe", "short_history"])
    func encodedJSONEqualsOracleJSON(_ name: String) throws {
        let c = try #require(try fixture()[name])
        let out = try #require(MuscleLoad.compute(c.inputs))
        let mine = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(out)) as? NSDictionary)
        let raw = try rawFixture()
        let expected = try #require((raw[name] as? [String: Any])?["expected"] as? NSDictionary)
        #expect(mine == expected)
    }

    // MARK: maths (independent of the fixture)

    func bench(_ n: Int, kg: Double? = 50) -> [MuscleLoad.LoggedSet] {
        Array(repeating: .init(exerciseKey: "Barbell Bench Press", kind: "reps", reps: 10, weightKg: kg, durationS: nil), count: n)
    }

    @Test func steadyWeeklyLoadIsBalancedAtOne() throws {
        let days = ["2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28"]
        let sessions = days.enumerated().map { MuscleLoad.LoggedSession(id: $0.offset, date: $0.element, startedAt: nil, endedAt: nil, sets: bench(3)) }
        let out = try #require(MuscleLoad.compute(.init(asOf: "2026-10-04", loggedSessions: sessions)))
        let chest = try #require(out.row(.chest))
        #expect(chest.status == .ok && chest.acute == 1500 && chest.chronic == 1500)
        #expect(chest.ratio == 1.0 && chest.band == .balanced)
        #expect(out.row(.frontDelts)?.acute == 750) // secondary 0.5
        #expect(out.row(.hamstrings)?.status == .notEnoughData && out.row(.hamstrings)?.firstLoad == nil)
    }

    @Test func bands() {
        #expect(MuscleLoad.band(nil) == nil)
        #expect(MuscleLoad.band(0.79) == .low)
        #expect(MuscleLoad.band(0.8) == .balanced && MuscleLoad.band(1.3) == .balanced)
        #expect(MuscleLoad.band(1.31) == .high)
    }

    @Test func noRecentLoadAfterLongGap() throws {
        let s = MuscleLoad.LoggedSession(id: 1, date: "2026-08-01", startedAt: nil, endedAt: nil, sets: bench(3))
        let out = try #require(MuscleLoad.compute(.init(asOf: "2026-10-04", loggedSessions: [s])))
        let chest = try #require(out.row(.chest))
        #expect(chest.status == .noRecentLoad && chest.ratio == nil && chest.band == nil)
        #expect(chest.lastLoad == "2026-08-01")
    }

    @Test func bodyweightWithoutAnyWeightIsSkippedNeverGuessed() throws {
        let pushUp = MuscleLoad.LoggedSet(exerciseKey: "Diamond Push-Up", kind: "reps", reps: 20, weightKg: 0, durationS: nil)
        let plank = MuscleLoad.LoggedSet(exerciseKey: "Plank", kind: "timed", reps: nil, weightKg: nil, durationS: 60)
        let s = MuscleLoad.LoggedSession(id: 1, date: "2026-10-04", startedAt: nil, endedAt: nil, sets: [pushUp, plank])
        let none = try #require(MuscleLoad.compute(.init(asOf: "2026-10-04", loggedSessions: [s])))
        #expect(none.skipped.bodyweightSetsNoWeight == 2 && none.row(.triceps)?.acute == 0)
        // a LATER weight is used when nothing is on/before the day
        let later = try #require(MuscleLoad.compute(.init(asOf: "2026-10-04", bodyWeight: [.init(date: "2026-10-04", weightKg: 80)], loggedSessions: [s])))
        #expect(later.row(.triceps)?.acute == 1040) // 20 × 0.65 × 80
        #expect(later.row(.core)?.acute == 1040)    // 60 s / 3 × 0.65 × 80
    }

    @Test func cardioCreditByActivityTypeOnly() throws {
        let run = MuscleLoad.Activity(id: 1, date: "2026-10-04", type: "Running", startUTC: nil, durationSec: 1800, teAerobic: nil, sets: [])
        let walk = MuscleLoad.Activity(id: 2, date: "2026-10-04", type: "walking", startUTC: nil, durationSec: 3600, teAerobic: 3, sets: [])
        let out = try #require(MuscleLoad.compute(.init(asOf: "2026-10-04", activities: [run, walk])))
        #expect(out.row(.quads)?.acute == 500 && out.row(.glutes)?.acute == 250) // 0.5 h × TE 1.0 × 1000
        #expect(out.row(.hamstrings)?.acute == 0)
    }

    @Test func dedupeOverlapWithSlackAndDifferentDay() throws {
        let logged = MuscleLoad.LoggedSession(id: 1, date: "2026-10-04", startedAt: "2026-10-04T17:00:00Z", endedAt: "2026-10-04T18:00:00Z", sets: bench(3))
        let g = MuscleLoad.GarminSet(exerciseName: "BARBELL_BENCH_PRESS", exerciseCategory: "BENCH_PRESS", reps: 10, weightKg: 50)
        func act(_ id: Int, _ date: String, _ start: String?) -> MuscleLoad.Activity {
            .init(id: id, date: date, type: "strength_training", startUTC: start, durationSec: 1800, teAerobic: nil, sets: [g])
        }
        let inputs = MuscleLoad.Inputs(asOf: "2026-10-04", activities: [
            act(1, "2026-10-04", "2026-10-04T18:10:00+00:00"), // starts 10 min after the end → within slack
            act(2, "2026-10-04", "2026-10-04T16:00:00.500Z"),  // 16:00–16:30, 30 min before → kept
            act(3, "2026-10-03", nil),                         // other day → kept
        ], loggedSessions: [logged])
        let out = try #require(MuscleLoad.compute(inputs))
        #expect(out.dedupedGarminActivities == [1])
        #expect(out.row(.chest)?.acute == 2500) // 1500 logged + 500 + 500
    }

    @Test func dataAfterAsOfIsIgnoredAndBadDateIsNil() throws {
        let s = MuscleLoad.LoggedSession(id: 1, date: "2026-10-05", startedAt: nil, endedAt: nil, sets: bench(3))
        let out = try #require(MuscleLoad.compute(.init(asOf: "2026-10-04", loggedSessions: [s])))
        #expect(out.muscles.allSatisfy { $0.acute == 0 && $0.status == .notEnoughData })
        #expect(MuscleLoad.compute(.init(asOf: "nope")) == nil)
    }

    @Test func dayArithmeticRoundTrips() throws {
        for s in ["2024-02-29", "2026-01-01", "2026-12-31", "2000-03-01", "1999-12-31"] {
            #expect(try #require(MuscleLoad.Day(s)).iso == s)
        }
        #expect(MuscleLoad.Day("2026-03-01")?.adding(-1).iso == "2026-02-28")
        #expect(MuscleLoad.Day("2026-10-04T23:59:00+02:00")?.iso == "2026-10-04")
    }

    @Test func parityRegistryEntry() {
        #expect(ParityRegistry.source(for: "muscle_load") == .computed)
        #expect(ParityRegistry.implementation(for: "muscle_load") == "JICompute.MuscleLoad")
    }
}
