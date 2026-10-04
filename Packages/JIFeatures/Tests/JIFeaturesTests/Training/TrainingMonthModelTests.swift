import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-B92 C-5 — the Planner's Month view (Bevel gap BP-1): grid, header words, Q1 (partial never
/// credited), Q2 (a past day is read-only), and the offline fallback (hub 404 → this phone's
/// planned snapshots, else the plan; past owed days `.unknown`, never missed).
@MainActor @Suite struct TrainingMonthModelTests {
    static func day(_ iso: String, _ state: TrainingCalendarDay.State, type: String = "strength",
                    name: String = "Day 1 Full Upper + Z2 40min") -> TrainingCalendarDay {
        TrainingCalendarDay(date: iso, planned: TrainingCalendarPlanned(name: name, type: type, source: "snapshot"), state: state)
    }

    static func september() -> TrainingCalendarMonth {
        let states: [TrainingCalendarDay.State] = [.done, .missed, .partial, .partial, .missed, .rest, .missed]
        let days = (1...30).map { d -> TrainingCalendarDay in
            let iso = String(format: "2026-09-%02d", d)
            if d == 30 { return Self.day(iso, .unknown) }
            return Self.day(iso, d <= 7 ? states[d - 1] : (d % 7 == 6 ? .rest : .missed), type: d % 7 == 6 ? "rest" : "strength")
        }
        return TrainingCalendarMonth(month: "2026-09", today: "2026-10-04", syncedThrough: "2026-09-29", days: days,
                                     summary: TrainingCalendarSummary(days: days))
    }

    struct StubProvider: TrainingCalendarProviding {
        var result: Result<TrainingCalendarMonth, any Error>
        func trainingCalendar(month: String) async throws -> TrainingCalendarMonth { try result.get() }
    }

    // MARK: pure helpers

    @Test func gridStartsOnMondayWithLeadingBlanks() {
        let grid = trainingMonthGrid(Self.september())
        #expect(grid.count % 7 == 0 && grid.count == 35)
        #expect(grid[0] == nil && grid[1]?.date == "2026-09-01")      // 1 Sep 2026 is a Tuesday
        #expect(grid.compactMap { $0 }.count == 30)
    }

    @Test func monthShiftAndTitle() {
        #expect(trainingMonthShift("2026-01", by: -1) == "2025-12")
        #expect(trainingMonthShift("2026-12", by: 1) == "2027-01")
        #expect(trainingMonthShift("2026-09", by: 1) == "2026-10")
        #expect(trainingMonthTitle("2026-09") == "September 2026")
    }

    @Test func headlineCountsOnlyDoneQ1() {
        let m = Self.september()
        #expect(m.summary.partial == 2)
        #expect(trainingMonthHeadline(m) == "\(m.summary.done) of \(m.summary.owedToDate) owed in September")
        #expect(trainingMonthDetail(m) == "2 partial · \(m.summary.missed) missed · 1 not synced yet")
        #expect(trainingMonthSyncLine(m) == "Activities synced to 29 Sep")
    }

    @Test func headlineWithNothingSyncedSaysNoData() {
        let days = [Self.day("2026-10-01", .unknown), Self.day("2026-10-02", .unknown), Self.day("2026-10-05", .planned)]
        let m = TrainingCalendarMonth(month: "2026-10", today: "2026-10-04", syncedThrough: "2026-09-29", days: days,
                                      summary: TrainingCalendarSummary(days: days))
        #expect(trainingMonthHeadline(m) == "— No data for October yet")
        #expect(trainingMonthDetail(m) == "2 not synced yet · 1 planned")
    }

    @Test func glyphsAndLabels() {
        #expect(TrainingCalendarDay.State.allCases.map(trainingMonthGlyph) == ["●", "◐", "✕", "?", "○", "–"])
        let label = trainingMonthCellLabel(Self.day("2026-09-21", .done))
        #expect(label == "Monday 21 September, Day 1 Full Upper + Z2 40min, done")
        #expect(trainingMonthCellLabel(Self.day("2026-09-30", .unknown)).hasSuffix("not synced yet"))
    }

    // MARK: the model

    @Test func pastDayIsReadOnlyTodayAndFutureAreNot() {
        let model = TrainingMonthModel(provider: nil, store: nil, today: { "2026-10-04" }, fallback: { _, _ in
            TrainingCalendarPlanned(name: "Rest", type: "rest", source: "table") })
        #expect(model.isReadOnly(Self.day("2026-10-03", .missed)))
        #expect(!model.isReadOnly(Self.day("2026-10-04", .planned)))
        #expect(!model.isReadOnly(Self.day("2026-10-05", .planned)))
    }

    @Test func hubMonthLoadsAndBackfillsTheSnapshotStore() async throws {
        let store = PlannedSnapshotStore(db: try AppDatabase.inMemory())
        let model = TrainingMonthModel(provider: StubProvider(result: .success(Self.september())), store: store,
                                       today: { "2026-10-04" }, month: "2026-09",
                                       fallback: { _, _ in TrainingCalendarPlanned(name: "x", type: "rest", source: "table") })
        await model.load()
        #expect(model.data?.month == "2026-09" && !model.isOffline)
        #expect(try store.snapshots(from: "2026-09-01", to: "2026-09-30").count == 30)
    }

    @Test func hub404FallsBackToDeviceSnapshotsThenThePlan() async throws {
        let store = PlannedSnapshotStore(db: try AppDatabase.inMemory())
        try store.record(TrainingCalendarPlanned(name: "Norwegian 4x4 intervals", type: "interval", source: "snapshot"),
                         on: "2026-09-21", today: "2026-10-04")
        let model = TrainingMonthModel(provider: StubProvider(result: .failure(TrainingCalendarUnavailable())), store: store,
                                       today: { "2026-10-04" }, month: "2026-09",
                                       fallback: { _, wd in TrainingCalendarPlanned(name: wd == 6 ? "Rest" : "Plan S", type: wd == 6 ? "rest" : "strength", source: "plan") })
        await model.load()
        let m = try #require(model.data)
        #expect(model.isOffline)
        let d21 = try #require(m.days.first { $0.date == "2026-09-21" })
        #expect(d21.planned.source == "device" && d21.planned.type == "interval" && d21.state == .unknown)
        #expect(m.days.first { $0.date == "2026-09-22" }?.planned.source == "plan")
        #expect(m.summary.missed == 0 && m.summary.done == 0)
    }

    @Test func shiftLoadsTheNextMonth() async {
        let model = TrainingMonthModel(provider: nil, store: nil, today: { "2026-10-04" }, month: "2026-10",
                                       fallback: { _, _ in TrainingCalendarPlanned(name: "S", type: "strength", source: "plan") })
        await model.shift(by: -1)
        #expect(model.month == "2026-09" && model.data?.days.count == 30)
    }
}
