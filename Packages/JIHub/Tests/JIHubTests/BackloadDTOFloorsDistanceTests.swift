import Foundation
import Testing
import JICore
@testable import JIHub

/// W9 L2 (B-30 P5): the hub's contract-v3 daily `floors` / `distance` arrays (HT e7720ff) decode
/// into `BackloadResponseDTO`; both default to `[]` when a pre-W9 hub omits the keys.
struct BackloadDTOFloorsDistanceTests {
    @Test func floorsAndDistanceDecodeWithVersion() throws {
        let json = """
        {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api",
         "sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],"workouts":[],
         "floors":[{"sync_id":"floors:2026-06-01","version":1789729180,"date":"2026-06-01","count":12}],
         "distance":[{"sync_id":"distance:2026-06-01","version":1789729180,"date":"2026-06-01","meters":6420.5}]}
        """
        let dto = try JSON.decoder.decode(BackloadResponseDTO.self, from: Data(json.utf8))
        #expect(dto.floors == [BackloadFloorsEntryDTO(syncId: "floors:2026-06-01", date: "2026-06-01", count: 12, version: 1789729180)])
        #expect(dto.distance == [BackloadDistanceEntryDTO(syncId: "distance:2026-06-01", date: "2026-06-01", meters: 6420.5, version: 1789729180)])
    }

    @Test func floorsAndDistanceDefaultToEmptyWhenAbsent() throws {
        let json = """
        {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api",
         "sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],"workouts":[]}
        """
        let dto = try JSON.decoder.decode(BackloadResponseDTO.self, from: Data(json.utf8))
        #expect(dto.floors.isEmpty)
        #expect(dto.distance.isEmpty)
    }
}
