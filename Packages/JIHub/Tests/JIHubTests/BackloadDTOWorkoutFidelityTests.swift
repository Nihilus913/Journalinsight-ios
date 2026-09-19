import Foundation
import Testing
import JICore
@testable import JIHub

/// W9 L1 (B-30 P3): contract v3 additive workout fields — `raw_type` (the Garmin activity type
/// string) and `indoor`. Absent on the wire (a pre-e7720ff hub) decodes to nil, so the DTO still
/// accepts a v2 response.
struct BackloadDTOWorkoutFidelityTests {
    @Test func workoutsDecodeRawTypeAndIndoorAndDefaultToNilWhenAbsent() throws {
        let json = """
        {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],
         "workouts":[
           {"sync_id":"workout:1","version":1789729180,"start":"2026-06-01T07:00:00+02:00","end":"2026-06-01T07:30:00+02:00","kind":"running","name":"Base","kcal":300,"distance_m":5000,"avg_hr":150,"raw_type":"treadmill_running","indoor":true},
           {"sync_id":"workout:2","start":"2026-06-01T18:00:00+02:00","end":"2026-06-01T19:00:00+02:00","kind":"strength","name":"Monday","kcal":400,"distance_m":null,"avg_hr":120}
         ]}
        """
        let dto = try JSON.decoder.decode(BackloadResponseDTO.self, from: Data(json.utf8))
        #expect(dto.workouts[0].rawType == "treadmill_running")
        #expect(dto.workouts[0].indoor == true)
        #expect(dto.workouts[1].rawType == nil)
        #expect(dto.workouts[1].indoor == nil)
    }
}
