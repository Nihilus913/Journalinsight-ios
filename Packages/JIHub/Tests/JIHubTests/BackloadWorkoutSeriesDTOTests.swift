import Foundation
import Testing
import JICore
@testable import JIHub

/// W11 L1 (B-30 P4): contract v4 additive per-workout series — `workout_hr` (per-second HR from
/// Garmin `activity/{id}/details`) and `workout_routes` (GPS points + ascent). Decodes the synced
/// fixture of record byte-for-byte as L0 exports it; a hub without the two arrays (pre-W11) still
/// decodes with both `nil`.
struct BackloadWorkoutSeriesDTOTests {
    private func fixtureData(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent() // .../Tests/JIHubTests
            .appending(path: "../../../../Fixtures/hub-contract/\(name).json").standardized
        return try Data(contentsOf: url)
    }

    @Test func fixtureOfRecordDecodesBothSeries() throws {
        let dto = try JSON.decoder.decode(BackloadResponseDTO.self, from: try fixtureData("vitals_backload_workout_series"))
        #expect(dto.from == "2026-09-03" && dto.to == "2026-09-04")
        #expect(dto.workouts.isEmpty && dto.heartRate.isEmpty)

        let hr = try #require(dto.workoutHr)
        #expect(hr.count == 2)
        #expect(hr[0].syncId == "workout:24218147086")
        #expect(hr[0].version == 1_790_000_000)
        #expect(hr[0].samples.count == 6)
        #expect(hr[0].samples.first == BackloadWorkoutHrSampleDTO(ts: "2026-09-03T03:51:03Z", bpm: 109))
        #expect(hr[0].samples.last?.bpm == 110)
        #expect(hr[1].syncId == "workout:24230557720")
        #expect(hr[1].version == 1_790_000_000)
        #expect(hr[1].samples.count == 4)
        #expect(hr[1].samples.map(\.bpm) == [93, 93, 98, 99])

        let routes = try #require(dto.workoutRoutes)
        #expect(routes.count == 1)
        let route = routes[0]
        #expect(route.syncId == "workout:24218147086")
        #expect(route.version == 1_790_000_000)
        #expect(route.ascentM == nil)
        #expect(route.points.count == 6)
        let p0 = route.points[0]
        #expect(p0.ts == "2026-09-03T03:51:03Z")
        #expect(p0.lat == 47.438225308433175)
        #expect(p0.lon == 8.47419991157949)
        #expect(p0.altM == 441.6000061035156)
        #expect(p0.speedMps == 1.1660000085830688)
        #expect(route.points.allSatisfy { $0.altM != nil && $0.speedMps != nil })
        #expect(route.points.last?.altM == 443.6000061035156)
    }

    @Test func absentArraysDecodeToNilAndNullOptionalsDecode() throws {
        let json = """
        {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],"workouts":[]}
        """
        let dto = try JSON.decoder.decode(BackloadResponseDTO.self, from: Data(json.utf8))
        #expect(dto.workoutHr == nil)
        #expect(dto.workoutRoutes == nil)

        let withNulls = """
        {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],"workouts":[],
         "workout_hr":[],
         "workout_routes":[{"sync_id":"workout:7","version":5,"ascent_m":12.5,"points":[
           {"ts":"2026-06-01T05:00:00Z","lat":47.4,"lon":8.4,"alt_m":null,"speed_mps":null},
           {"ts":"2026-06-01T05:00:01Z","lat":47.5,"lon":8.5,"alt_m":400.0,"speed_mps":2.0}]}]}
        """
        let dto2 = try JSON.decoder.decode(BackloadResponseDTO.self, from: Data(withNulls.utf8))
        #expect(dto2.workoutHr == [])
        let r = try #require(dto2.workoutRoutes?.first)
        #expect(r.ascentM == 12.5)
        #expect(r.points[0].altM == nil && r.points[0].speedMps == nil)
        #expect(r.points[1].altM == 400.0 && r.points[1].speedMps == 2.0)
    }

    /// `merge`-style reconstruction through the memberwise init must round-trip through Codable.
    @Test func encodeDecodeRoundTrip() throws {
        let entry = BackloadWorkoutHrEntryDTO(syncId: "workout:1", version: 9, samples: [.init(ts: "2026-06-01T05:00:00Z", bpm: 100)])
        let route = BackloadWorkoutRouteEntryDTO(syncId: "workout:1", version: 9, ascentM: 3, points: [.init(ts: "2026-06-01T05:00:00Z", lat: 1, lon: 2, altM: 3, speedMps: nil)])
        let dto = BackloadResponseDTO(from: "a", to: "b", source: "s", sleep: [], rhr: [], steps: [], energy: [], vo2max: [], workouts: [], workoutHr: [entry], workoutRoutes: [route])
        let data = try JSON.encoder.encode(dto)
        let back = try JSON.decoder.decode(BackloadResponseDTO.self, from: data)
        #expect(back == dto)
    }
}
