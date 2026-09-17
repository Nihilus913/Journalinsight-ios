import Foundation
import Testing
import JICore
@testable import JIHub

// Local inline fixture (not the synced `Fixtures/hub-contract/` tree — see CLAUDE.md "Fixtures"
// note: those are copies synced by HealthTraining's sync_fixtures.py and manifest-checked; a W2h
// fixture isn't landed there yet, so this test mirrors HubClientTests' own inline-JSON pattern).
private let backloadFixtureJSON = """
{
  "from": "2025-06-01", "to": "2025-06-30", "source": "garmin_api",
  "sleep": [
    { "sync_id": "sleep:2025-06-01", "start": "2025-06-01T22:30:00+02:00", "end": "2025-06-02T06:45:00+02:00",
      "asleep_sec": 24300, "deep_sec": 5400, "light_sec": 14400, "rem_sec": 4500, "awake_sec": 600 }
  ],
  "rhr": [ { "sync_id": "rhr:2025-06-01", "date": "2025-06-01", "bpm": 52.0 } ],
  "steps": [ { "sync_id": "steps:2025-06-01", "date": "2025-06-01", "count": 8421.0 } ],
  "energy": [ { "sync_id": "energy:2025-06-01", "date": "2025-06-01", "active_kcal": 512.0, "basal_kcal": 1750.0 } ],
  "vo2max": [ { "sync_id": "vo2max:2025-06-01", "date": "2025-06-01", "value": 47.5 } ],
  "workouts": [
    { "sync_id": "workout:123", "start": "2025-06-01T18:00:00+02:00", "end": "2025-06-01T19:00:00+02:00",
      "kind": "strength", "name": "Full Upper", "kcal": 420.0, "distance_m": null, "avg_hr": 128.0 }
  ]
}
"""

// Merged into HubClientTests' `.serialized` suite (see HubDataProviderTests.swift's own note on
// why: two independent `.serialized` suites still raced on StubURLProtocol's process-global state).
extension HubClientTests {
    @Test func backloadClientDecodesContractFixture() async throws {
        StubURLProtocol.responses["/api/v1/health/backload"] = (200, Data(backloadFixtureJSON.utf8))
        let client = BackloadClient(hub: HubClient(config: .init(baseURL: URL(string: "http://hub.test:8000")!, token: "t"), session: StubURLProtocol.session()))

        var zurich = Calendar(identifier: .gregorian)
        zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let from = zurich.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let to = zurich.date(from: DateComponents(year: 2025, month: 6, day: 30))!

        let dto = try await client.fetch(from: from, to: to)
        #expect(dto.from == "2025-06-01")
        #expect(dto.source == "garmin_api")
        #expect(dto.sleep.first?.syncId == "sleep:2025-06-01")
        #expect(dto.sleep.first?.asleepSec == 24300)
        #expect(dto.rhr.first?.bpm == 52.0)
        #expect(dto.steps.first?.count == 8421.0)
        #expect(dto.energy.first?.activeKcal == 512.0)
        #expect(dto.vo2max.first?.value == 47.5)
        #expect(dto.workouts.first?.kind == .strength)
        #expect(dto.workouts.first?.distanceM == nil)
        #expect(dto.workouts.first?.avgHr == 128.0)
        #expect(StubURLProtocol.lastRequest?.url?.query?.contains("from=2025-06-01") == true)
        #expect(StubURLProtocol.lastRequest?.url?.query?.contains("to=2025-06-30") == true)
    }
}
