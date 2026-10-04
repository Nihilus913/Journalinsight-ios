import Foundation
import Testing
@testable import JICore

/// W-B92 C-3 — `GET /api/v1/training/calendar?month=` (HT `app/training/calendar.py`). The JSON is
/// HT's golden verbatim (`HealthTraining/tests/fixtures/b92/calendar_golden.json`, copied to
/// `Resources/b92/`): June 2026 with today = 20 Jun, activities synced to 11 Jun, first week.
@Suite struct B92TrainingCalendarTests {
    static func golden() throws -> TrainingCalendarMonth {
        let url = try #require(Bundle.module.url(forResource: "calendar_golden", withExtension: "json", subdirectory: "Resources/b92"))
        return try JSON.decoder.decode(TrainingCalendarMonth.self, from: Data(contentsOf: url))
    }

    @Test func decodesTheHubGolden() throws {
        let m = try Self.golden()
        #expect(m.month == "2026-06" && m.today == "2026-06-20" && m.syncedThrough == "2026-06-11")
        #expect(m.days.map(\.state) == [.done, .missed, .partial, .partial, .missed, .missed, .rest])
        let d1 = m.days[0]
        #expect(d1.planned.name == "Day 1 Full Upper + Z2 40min" && d1.planned.type == "strength" && d1.planned.source == "table")
        #expect(d1.credited && d1.status == "done" && d1.activities.map(\.activityId) == [9_200_001, 9_200_002])
        #expect(d1.activities[1].durationSec == 2700 && d1.activities[1].z2Share == nil)
        #expect(m.days[3].planned.source == "snapshot" && m.days[3].planned.prescription == "Day 2 Full Upper + Z2 60min")
        #expect(m.summary == TrainingCalendarSummary(done: 2, partial: 2, missed: 6, unknown: 7, planned: 9, rest: 4, owedToDate: 17))
    }

    @Test func anUnknownStateFromANewerHubIsUnknownNotMissed() throws {
        let json = """
        {"date": "2026-06-01", "planned": {"name": "x", "type": "strength", "source": "plan"},
         "state": "skipped_by_coach", "status": null, "credited": false, "activities": []}
        """
        let d = try JSON.decoder.decode(TrainingCalendarDay.self, from: Data(json.utf8))
        #expect(d.state == .unknown && d.planned.sessionType == nil && d.planned.templateId == nil)
    }

    @Test func plannedLetterPerType() {
        #expect(TrainingCalendarPlanned.letter(forType: "strength") == "S")
        #expect(TrainingCalendarPlanned.letter(forType: "interval") == "I")
        #expect(TrainingCalendarPlanned.letter(forType: "z2") == "Z")
        #expect(TrainingCalendarPlanned.letter(forType: "rest") == nil)
    }

    @Test func mockServesAMonthOfPlannedDays() async throws {
        let m = try await MockDataProvider().trainingCalendar(month: "2026-10")
        #expect(m.month == "2026-10" && m.days.count == 31 && m.days.first?.date == "2026-10-01")
        #expect(m.days.allSatisfy { $0.activities.isEmpty })
    }

    @Test func datesOfAMonthAreMondayZero() throws {
        let d = try #require(TrainingCalendarMonth.dates(of: "2026-09"))
        #expect(d.count == 30 && d[0].iso == "2026-09-01" && d[0].weekday == 1)   // Tue 1 Sep 2026
        #expect(try #require(TrainingCalendarMonth.dates(of: "2024-02")).count == 29)
        #expect(TrainingCalendarMonth.dates(of: "2026-13") == nil && TrainingCalendarMonth.dates(of: "x") == nil)
    }

    @Test func offlinePastOwedIsUnknownNeverMissed() throws {
        let m = try #require(TrainingCalendarMonth.offline(month: "2026-10", today: "2026-10-04") { _, wd in
            TrainingCalendarPlanned(name: wd == 6 ? "Rest" : "S", type: wd == 6 ? "rest" : "strength", source: "table")
        })
        #expect(m.days[0].state == .unknown && m.days[2].state == .unknown)     // 1–3 Oct past
        #expect(m.days[3].state == .rest)                                       // Sun 4 Oct
        #expect(m.days[4].state == .planned)                                    // Mon 5 Oct
        #expect(m.summary.missed == 0 && m.summary.done == 0 && m.summary.unknown == 3 && m.summary.owedToDate == 3)
    }
}
