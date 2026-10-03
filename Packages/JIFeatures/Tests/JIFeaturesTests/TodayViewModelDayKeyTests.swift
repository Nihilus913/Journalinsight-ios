import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-KEYS K2: Today's "today" is the phone-zone `DayKey`, not the UTC prefix — at 00:30 Zurich on a
/// Monday the scheduled session is Monday's, not Sunday's (the scout's midnight bug).
@Suite struct TodayViewModelDayKeyTests {
    @Test @MainActor func midnightZurichIsNewDay() async throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-04T22:30:00Z")! // Mon 2026-10-05 00:30 Zurich
        let vm = TodayViewModel(provider: Fix10TodayProvider(plan: fix10MovedPlan, reason: nil),
                                cache: OfflineCache(db: try AppDatabase.inMemory()), now: { now },
                                zone: { TimeZone(identifier: "Europe/Zurich")! })
        await vm.load()
        let monday = scheduledSession(on: "2026-10-05", planSessions: fix10MovedPlan)?.name
        let sunday = scheduledSession(on: "2026-10-04", planSessions: fix10MovedPlan)?.name
        #expect(monday != nil && monday != sunday)
        #expect(vm.scheduledSessionToday == monday)
    }
}
