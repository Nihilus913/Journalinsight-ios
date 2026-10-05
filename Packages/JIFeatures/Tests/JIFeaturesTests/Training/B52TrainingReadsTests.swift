#if canImport(WorkoutKit)
import Foundation
import Testing
import JICore
import JIPersistence
import JIWorkouts
@testable import JIFeatures

// B-52 p2 (reads: training) — every training read answered from the hub's offline read-through
// cache shows the last-known data + an "Offline — showing data from …" line (never blank, never
// a fresh-looking answer), and a cold cache stays an explicit empty/error state.
//
// The stubs play `HubClient.getRead`'s part: a stale answer is recorded in `HubReadTrace.current`
// exactly as the client does when it serves a cached copy (see JIHub `HubClientReadCacheTests`).

private let cachedAt = ISO8601DateFormatter().date(from: "2026-10-04T07:41:00Z")!

/// What `HubClient` does when the hub is unreachable and a copy exists.
private nonisolated func serveStale(_ key: String) { HubReadTrace.current?.record(key, fetchedAt: cachedAt) }

private actor B52BreakHub: TrainingBreakProviding {
    var mode: Mode = .fresh
    enum Mode { case fresh, stale, cold }
    func setMode(_ m: Mode) { mode = m }
    func trainingBreak() async throws -> TrainingBreak {
        switch mode {
        case .fresh: return TrainingBreak(paused: true, since: "2026-09-28")
        case .stale: serveStale("hub:GET /api/v1/planning/training-break"); return TrainingBreak(paused: true, since: "2026-09-28")
        case .cold: throw HubError.network("offline")
        }
    }
    func setTrainingBreak(paused: Bool, since: String?) async throws -> TrainingBreak { TrainingBreak(paused: paused, since: since) }
}

private nonisolated final class B52TemplatesHub: WorkoutTemplatesProviding, @unchecked Sendable {
    var rows: [WorkoutTemplate]; var stale: Bool; var fail: Bool
    init(rows: [WorkoutTemplate], stale: Bool = false, fail: Bool = false) { self.rows = rows; self.stale = stale; self.fail = fail }
    func workoutTemplates() async throws -> [WorkoutTemplate] {
        if fail { throw HubError.network("offline") }
        if stale { serveStale("hub:GET /api/v1/planning/workout-templates") }
        return rows
    }
}

private struct B52CalendarHub: TrainingCalendarProviding {
    let month: TrainingCalendarMonth; let stale: Bool
    func trainingCalendar(month: String) async throws -> TrainingCalendarMonth {
        if stale { serveStale("hub:GET /api/v1/training/calendar?month=\(month)") }
        return self.month
    }
}

@MainActor @Suite(.serialized) struct B52TrainingReadsTests {

    @Test func captionSaysOfflineWithTheCopysTime() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!; cal.locale = Locale(identifier: "en_GB")
        #expect(offlineReadCaption(since: cachedAt, now: cachedAt.addingTimeInterval(3600), calendar: cal) == "Offline — showing data from 07:41")
        #expect(offlineReadCaption(since: cachedAt, now: cachedAt.addingTimeInterval(2 * 86_400), calendar: cal) == "Offline — showing data from 4 Oct, 07:41")
    }

    // Training break (Settings): stale copy = last-known state + offline line; cold = explicit error.
    @Test func trainingBreakShowsTheCachedStateOffline() async {
        let hub = B52BreakHub()
        await hub.setMode(.stale)
        let m = TrainingBreakViewModel(provider: hub)
        await m.load()
        #expect(m.paused && m.sinceText == "On a break since 28 Sep")
        #expect(m.staleSince == cachedAt && m.offlineText?.hasPrefix("Offline — showing data from") == true)
        #expect(m.errorMessage == nil)
        await hub.setMode(.fresh)
        await m.load()
        #expect(m.staleSince == nil && m.offlineText == nil)
    }

    @Test func trainingBreakColdCacheIsAnExplicitError() async {
        let hub = B52BreakHub()
        await hub.setMode(.cold)
        let m = TrainingBreakViewModel(provider: hub)
        await m.load()
        #expect(m.state == nil && m.errorMessage != nil)
    }

    @Test func trainingBreakKeepsTheShownStateWhenARefreshFails() async {
        let hub = B52BreakHub()
        let m = TrainingBreakViewModel(provider: hub)
        await m.load()
        await hub.setMode(.cold)
        await m.load()
        #expect(m.paused && m.errorMessage == nil)
    }

    // Calendar month: the hub's cached month (done/missed as it last knew) beats the phone-built one.
    @Test func monthUsesTheCachedHubAnswerOffline() async {
        let sept = TrainingMonthModelTests.september()
        let m = TrainingMonthModel(provider: B52CalendarHub(month: sept, stale: true), store: nil, today: { "2026-10-04" },
                                   month: "2026-09", fallback: { _, _ in TrainingCalendarPlanned(name: "x", type: "rest", source: "plan") })
        await m.load()
        #expect(m.data == sept)
        #expect(m.isOffline && m.staleSince == cachedAt)
        let fresh = TrainingMonthModel(provider: B52CalendarHub(month: sept, stale: false), store: nil, today: { "2026-10-04" },
                                       month: "2026-09", fallback: { _, _ in TrainingCalendarPlanned(name: "x", type: "rest", source: "plan") })
        await fresh.load()
        #expect(!fresh.isOffline && fresh.staleSince == nil)
    }

    // Workout library (Planner): a cached copy must still read OFFLINE — Push/Import stay disabled.
    @Test func libraryServedFromCacheStaysOffline() async throws {
        let rows = try await MockDataProvider().workoutTemplates()
        let db = try AppDatabase.inMemory()
        let hub = B52LibraryHub(rows: rows); hub.stale = true
        let vm = WorkoutLibraryViewModel(provider: hub, cache: OfflineCache(db: db), outbox: Outbox(db: db))
        await vm.refresh()
        #expect(vm.state == .loaded && !vm.templates.isEmpty)
        #expect(!vm.hubReachable && vm.fetchedAt == cachedAt)
        #expect(vm.garminDisabledReason != nil)
        hub.stale = false
        await vm.refresh()
        #expect(vm.hubReachable && vm.garminDisabledReason == nil)
    }

    // Send to Watch: the cached list renders with the offline line; a cold cache says so.
    @Test func sendToWatchListsTheCachedTemplatesOffline() async throws {
        let rows = try await MockDataProvider().workoutTemplates()
        let vm = SendToWatchViewModel(provider: B52TemplatesHub(rows: rows, stale: true), sender: FakeWorkoutSender(),
                                      builder: { _ in throw HubError.network("unused") })
        await vm.load()
        #expect(!vm.templates.isEmpty && vm.state == .idle)
        #expect(vm.staleSince == cachedAt && vm.offlineText != nil)
    }

    @Test func sendToWatchColdCacheIsAnExplicitEmptyState() async {
        let vm = SendToWatchViewModel(provider: B52TemplatesHub(rows: [], fail: true), sender: FakeWorkoutSender(),
                                      builder: { _ in throw HubError.network("unused") })
        await vm.load()
        #expect(vm.templates.isEmpty)
        #expect(sendToWatchEmptyText(state: vm.state).hasPrefix("No cached workout templates yet"))
        #expect(sendToWatchEmptyText(state: .idle) == "No workout templates on the hub.")
    }
}

/// A `WorkoutLibraryProviding` whose read can be served "from cache" (the writes are unused here).
private nonisolated final class B52LibraryHub: WorkoutLibraryProviding, @unchecked Sendable {
    let inner: FakeWorkoutHub
    var stale = false
    init(rows: [WorkoutTemplate]) { inner = FakeWorkoutHub(rows: rows) }
    func workoutTemplates() async throws -> [WorkoutTemplate] {
        if stale { serveStale("hub:GET /api/v1/planning/workout-templates") }
        return try await inner.workoutTemplates()
    }
    func createWorkoutTemplate(_ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate { try await inner.createWorkoutTemplate(draft) }
    func updateWorkoutTemplate(id: Int, _ draft: WorkoutTemplateDraft) async throws -> WorkoutTemplate { try await inner.updateWorkoutTemplate(id: id, draft) }
    func deleteWorkoutTemplate(id: Int) async throws { try await inner.deleteWorkoutTemplate(id: id) }
    func pushWorkoutTemplateToGarmin(id: Int) async throws -> GarminPushResult { try await inner.pushWorkoutTemplateToGarmin(id: id) }
    func importWorkoutsFromGarmin() async throws -> GarminImportReport { try await inner.importWorkoutsFromGarmin() }
}
#endif
