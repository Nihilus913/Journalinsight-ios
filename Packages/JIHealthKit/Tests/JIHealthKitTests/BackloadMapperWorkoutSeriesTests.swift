import Foundation
import Testing
import JICore
import JIHub
@testable import JIHealthKit

/// W11 L1 (B-30 P4): per-workout series from the hub's v4 `workout_hr` / `workout_routes` arrays.
/// A workout whose sync id has a `workout_hr` entry takes THAT series (per-second, from
/// `activity/{id}/details`) and never the W9 windowed dense selection; one without falls back to
/// W9 exactly as before. The route comes from the matching `workout_routes` entry.
struct BackloadMapperWorkoutSeriesTests {
    /// Two workouts: the 2026-09-03 run (per-second HR + route, values from the fixture of record)
    /// and the 2026-09-04 strength session (per-second HR, no route). The dense `heart_rate` array
    /// has 2-min readings inside BOTH windows, which must be ignored for these two, plus a third
    /// workout with no `workout_hr` entry that still gets the W9 windowed selection.
    private var json: String { """
    {"from":"2026-09-03","to":"2026-09-04","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],
     "workouts":[
       {"sync_id":"workout:24218147086","version":1789729180,"start":"2026-09-03T05:51:00+02:00","end":"2026-09-03T06:09:24+02:00","kind":"running","name":"katzensee","kcal":300,"distance_m":3000,"avg_hr":150,"raw_type":"running","indoor":false},
       {"sync_id":"workout:24230557720","version":1789729181,"start":"2026-09-04T05:58:00+02:00","end":"2026-09-04T06:58:00+02:00","kind":"strength","name":"Thursday","kcal":400,"distance_m":null,"avg_hr":120,"raw_type":"strength_training","indoor":true},
       {"sync_id":"workout:3","version":1789729182,"start":"2026-09-04T12:00:00+02:00","end":"2026-09-04T12:30:00+02:00","kind":"walking","name":"walk","kcal":100,"distance_m":2000,"avg_hr":null,"raw_type":"walking","indoor":false}
     ],
     "heart_rate":[
       {"ts":"2026-09-03T05:52:00+02:00","bpm":120},
       {"ts":"2026-09-04T06:00:00+02:00","bpm":95},
       {"ts":"2026-09-04T12:10:00+02:00","bpm":88}
     ],
     "workout_hr":[
       {"sync_id":"workout:24218147086","version":1790000000,"samples":[
         {"ts":"2026-09-03T03:51:03Z","bpm":109},{"ts":"2026-09-03T03:51:04Z","bpm":108},{"ts":"2026-09-03T03:51:05Z","bpm":108},
         {"ts":"2026-09-03T03:51:06Z","bpm":109},{"ts":"2026-09-03T03:51:07Z","bpm":110},{"ts":"2026-09-03T03:51:08Z","bpm":110}]},
       {"sync_id":"workout:24230557720","version":1790000000,"samples":[
         {"ts":"2026-09-04T03:58:36Z","bpm":93},{"ts":"2026-09-04T03:58:37Z","bpm":93},{"ts":"2026-09-04T03:58:38Z","bpm":98},{"ts":"2026-09-04T03:58:39Z","bpm":99}]}
     ],
     "workout_routes":[
       {"sync_id":"workout:24218147086","version":1790000000,"ascent_m":12.5,"points":[
         {"ts":"2026-09-03T03:51:03Z","lat":47.438225308433175,"lon":8.47419991157949,"alt_m":441.6000061035156,"speed_mps":1.1660000085830688},
         {"ts":"2026-09-03T03:51:04Z","lat":47.43824006058276,"lon":8.474185829982162,"alt_m":441.79998779296875,"speed_mps":1.2410000562667847},
         {"ts":"2026-09-03T03:51:05Z","lat":47.43825942277908,"lon":8.474190691486001,"alt_m":null,"speed_mps":null},
         {"ts":"2026-09-03T03:51:06Z","lat":47.438272750005126,"lon":8.474195804446936,"alt_m":442.0,"speed_mps":1.6890000104904175},
         {"ts":"2026-09-03T03:51:07Z","lat":47.438282892107964,"lon":8.474203683435917,"alt_m":442.20001220703125,"speed_mps":1.7079999446868896},
         {"ts":"2026-09-03T03:51:08Z","lat":47.43829395622015,"lon":8.474223548546433,"alt_m":443.6000061035156,"speed_mps":1.7079999446868896}]}
     ]}
    """ }

    private func specs() throws -> [String: BackloadWorkoutSampleSpec] {
        let dto = try JSON.decoder.decode(BackloadResponseDTO.self, from: Data(json.utf8))
        let workouts: [BackloadWorkoutSampleSpec] = BackloadMapper.map(dto).compactMap {
            if case .workout(let w) = $0 { return w } else { return nil }
        }
        return Dictionary(uniqueKeysWithValues: workouts.map { ($0.syncId, $0) })
    }

    @Test func workoutHrEntryReplacesTheWindowedDenseSelectionNeverBoth() throws {
        let s = try specs()
        let run = try #require(s["workout:24218147086"])
        #expect(run.hrSamples.count == 6)
        #expect(run.hrSamples.map(\.bpm) == [109, 108, 108, 109, 110, 110])
        #expect(run.hrSamples.first?.ts == BackloadDateParsing.timestamp("2026-09-03T03:51:03Z"))
        // the 05:52 dense reading falls inside the run's window but must NOT be merged in
        #expect(!run.hrSamples.contains { $0.bpm == 120 })

        let strength = try #require(s["workout:24230557720"])
        #expect(strength.hrSamples.map(\.bpm) == [93, 93, 98, 99])
        #expect(!strength.hrSamples.contains { $0.bpm == 95 })
    }

    @Test func workoutWithoutAnEntryKeepsTheW9WindowedSelection() throws {
        let walk = try #require(try specs()["workout:3"])
        #expect(walk.hrSamples.map(\.bpm) == [88])
        #expect(walk.route.isEmpty)
        #expect(walk.ascentM == nil)
    }

    @Test func routeRidesOnTheSpecWithOptionalAltitudeAndSpeed() throws {
        let run = try #require(try specs()["workout:24218147086"])
        #expect(run.ascentM == 12.5)
        #expect(run.route.count == 6)
        let p0 = run.route[0]
        #expect(p0.ts == BackloadDateParsing.timestamp("2026-09-03T03:51:03Z"))
        #expect(p0.lat == 47.438225308433175)
        #expect(p0.lon == 8.47419991157949)
        #expect(p0.altM == 441.6000061035156)
        #expect(p0.speedMps == 1.1660000085830688)
        #expect(run.route[2].altM == nil && run.route[2].speedMps == nil)
        #expect(run.route.map(\.ts) == run.route.map(\.ts).sorted())
        // no-GPS activity: no route, no ascent
        let strength = try #require(try specs()["workout:24230557720"])
        #expect(strength.route.isEmpty && strength.ascentM == nil)
    }

    @Test func absentV4ArraysAreByteIdenticalToW9() throws {
        let dto = try JSON.decoder.decode(BackloadResponseDTO.self, from: Data(json.utf8))
        let w9 = BackloadResponseDTO(
            from: dto.from, to: dto.to, source: dto.source, sleep: [], rhr: [], steps: [], energy: [], vo2max: [],
            workouts: dto.workouts, heartRate: dto.heartRate)
        let w9Specs = BackloadMapper.map(w9)
        let expected = BackloadMapper.map(BackloadResponseDTO(
            from: dto.from, to: dto.to, source: dto.source, sleep: [], rhr: [], steps: [], energy: [], vo2max: [],
            workouts: dto.workouts, heartRate: dto.heartRate, workoutHr: nil, workoutRoutes: nil))
        #expect(w9Specs == expected)
        let run = try #require(w9Specs.compactMap { if case .workout(let w) = $0, w.syncId == "workout:24218147086" { return w } else { return nil } }.first)
        #expect(run.hrSamples.map(\.bpm) == [120])
        #expect(run.route.isEmpty)
    }

    @Test func densePassRequestsTheTwoNewKinds() {
        #expect(BackloadMonthChunker.densePassKinds.isSuperset(of: ["workout_hr", "workout_routes"]))
        #expect(!BackloadMonthChunker.dailyPassKinds.contains("workout_hr"))
        #expect(!BackloadMonthChunker.dailyPassKinds.contains("workout_routes"))
    }
}
