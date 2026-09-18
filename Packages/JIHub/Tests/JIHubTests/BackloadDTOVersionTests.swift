import Foundation
import Testing
import JICore
@testable import JIHub

/// B-30 writer v4: every daily entry carries the hub row's `version` (updated_at epoch seconds,
/// additive to contract v2) — absent on the wire decodes to nil, present decodes to the int.
struct BackloadDTOVersionTests {
    @Test func dailyEntriesDecodeVersionWhenPresentAndNilWhenAbsent() throws {
        let json = """
        {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api",
         "sleep":[{"sync_id":"sleep:2026-06-01","version":1789729180,"start":"2026-06-01T22:00:00+02:00","end":"2026-06-02T06:00:00+02:00",
           "asleep_sec":28000,"deep_sec":5000,"light_sec":15000,"rem_sec":4000,"awake_sec":800}],
         "rhr":[{"sync_id":"rhr:2026-06-01","version":1789729180,"date":"2026-06-01","bpm":58}],
         "steps":[{"sync_id":"steps:2026-06-01","date":"2026-06-01","count":9000}],
         "energy":[{"sync_id":"energy:2026-06-01","version":1789729180,"date":"2026-06-01","active_kcal":500,"basal_kcal":1700}],
         "vo2max":[{"sync_id":"vo2max:2026-06-01","version":1789729180,"date":"2026-06-01","value":48.5}],
         "workouts":[{"sync_id":"workout:1","version":1789729180,"start":"2026-06-01T07:00:00+02:00","end":"2026-06-01T07:30:00+02:00","kind":"running","name":"Base","kcal":300,"distance_m":5000,"avg_hr":150}],
         "daily_resp":[{"sync_id":"resp:2026-06-01","version":1789729180,"date":"2026-06-01","waking_avg":15.0,"sleep_avg":12.0}],
         "daily_spo2":[{"sync_id":"spo2:2026-06-01","version":1789729180,"date":"2026-06-01","sleep_avg":95.0}]}
        """
        let dto = try JSON.decoder.decode(BackloadResponseDTO.self, from: Data(json.utf8))
        #expect(dto.sleep[0].version == 1789729180)
        #expect(dto.rhr[0].version == 1789729180)
        #expect(dto.steps[0].version == nil)
        #expect(dto.energy[0].version == 1789729180)
        #expect(dto.vo2max[0].version == 1789729180)
        #expect(dto.workouts[0].version == 1789729180)
        #expect(dto.dailyResp[0].version == 1789729180)
        #expect(dto.dailySpo2[0].version == 1789729180)
    }
}
