import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-B98A B98-4 — Activity detail (B-98 5a): the route's JSON decodes into the screen's rows,
/// the HR-only state for GPS-less Apple runs, the load phases, and the tap entry on the
/// completed-workout row. Payloads = real hub answers (throwaway hub :8812, HT b98p2, prod read-only).
@Suite struct ActivityDetailTests {
    /// 23926763203 — all 7 splits as served; points trimmed.
    static let garmin = """
    {"activity_id":23926763203,"type":"running","splits":[\
    {"km":1,"distance_m":1000.0,"duration_s":840.55,"pace_s_per_km":840.55,"mean_hr":121.1,"elevation_gain_m":7.3},\
    {"km":2,"distance_m":1000.0,"duration_s":777.01,"pace_s_per_km":777.01,"mean_hr":124.2,"elevation_gain_m":5.3},\
    {"km":3,"distance_m":1000.0,"duration_s":751.32,"pace_s_per_km":751.32,"mean_hr":122.5,"elevation_gain_m":5.0},\
    {"km":4,"distance_m":1000.0,"duration_s":689.67,"pace_s_per_km":689.67,"mean_hr":121.8,"elevation_gain_m":12.9},\
    {"km":5,"distance_m":1000.0,"duration_s":655.69,"pace_s_per_km":655.69,"mean_hr":124.6,"elevation_gain_m":6.4},\
    {"km":6,"distance_m":1000.0,"duration_s":605.29,"pace_s_per_km":605.29,"mean_hr":null,"elevation_gain_m":null},\
    {"km":7,"distance_m":694.21,"duration_s":482.46,"pace_s_per_km":694.99,"mean_hr":119.2,"elevation_gain_m":5.3}],\
    "points":[{"t":0.0,"hr":92.9,"pace_s_per_km":null},{"t":720.0,"hr":124.5,"pace_s_per_km":771.0},{"t":736.0,"hr":null,"pace_s_per_km":767.2}],\
    "hr_only":false,"caption":"JI-computed, may differ from Garmin"}
    """
    static let appleHrOnly = """
    {"activity_id":8000000000000009,"type":"running","splits":[],"points":[{"t":0.0,"hr":117.0,"pace_s_per_km":null},{"t":60.0,"hr":120.0,"pace_s_per_km":null}],"hr_only":true,"caption":"JI-computed, may differ from Garmin"}
    """

    static func decode(_ s: String) throws -> ActivitySeries { try JSON.decoder.decode(ActivitySeries.self, from: Data(s.utf8)) }

    @Test func routeJsonDecodes() throws {
        let s = try Self.decode(Self.garmin)
        #expect(s.activityId == 23926763203 && s.splits.count == 7 && s.points.count == 3 && !s.hrOnly)
        #expect(s.splits[5].meanHr == nil && s.splits[5].elevationGainM == nil)
        #expect(s.points[0].paceSPerKm == nil && s.points[2].hr == nil)
        let a = try Self.decode(Self.appleHrOnly)
        #expect(a.activityId == 8000000000000009 && a.hrOnly && a.splits.isEmpty)
    }

    @Test func paceReadsMinutesSecondsPerKm() {
        #expect(activityPaceText(840.55) == "14:01")
        #expect(activityPaceText(605.29) == "10:05")
        #expect(activityPaceText(359.6) == "6:00")
        #expect(activityPaceText(nil) == nil)
        #expect(activityPaceText(.nan) == nil)
    }

    @Test func splitRowsCarryEveryValueAndNeverAZero() throws {
        let rows = activitySplitRows(try Self.decode(Self.garmin))
        #expect(rows.map(\.pace) == ["14:01", "12:57", "12:31", "11:30", "10:56", "10:05", "11:35"])
        #expect(rows.first == ActivitySplitRow(id: 1, label: "1", pace: "14:01", hr: "121", elevation: "+7"))
        // Missing HR / elevation read as a dash (rule 5), never "0".
        #expect(rows[5].hr == "–" && rows[5].elevation == "–")
        // The last partial km says how far it went.
        #expect(rows[6].label == "0.69 km")
    }

    @Test func hrOnlyRunHasNoSplitsNoPaceAndSaysWhy() throws {
        let s = try Self.decode(Self.appleHrOnly)
        #expect(activitySplitRows(s).isEmpty)
        #expect(activityChartPoints(s).allSatisfy { $0.pace == nil })
        #expect(activityHrOnlyNote(s) == "HR only — this workout has no GPS or speed, so no pace or splits.")
        #expect(activityHrOnlyNote(try Self.decode(Self.garmin)) == nil)
    }

    @Test func chartPointsAreInMinutesAndSkipGaps() throws {
        let p = activityChartPoints(try Self.decode(Self.garmin))
        #expect(p.map(\.minute) == [0, 12, 736.0 / 60])
        #expect(p.compactMap(\.hr) == [92.9, 124.5])
        #expect(p.compactMap(\.pace) == [771.0 / 60, 767.2 / 60])
    }

    @Test func axisLabelsReadSecondsOnShortWorkouts() {
        #expect(activityAxisMinuteText(25, span: 80) == "25 min")
        #expect(activityAxisMinuteText(0.5, span: 1.8) == "0:30")
        #expect(activityAxisMinuteText(1.25, span: 1.8) == "1:15")
    }

    @Test @MainActor func modelLoadsTheSeries() async throws {
        let model = ActivityDetailModel(activity: Self.activity, provider: FakeSeries(result: .success(try Self.decode(Self.garmin))))
        #expect(model.phase == .loading)
        await model.load()
        guard case .loaded(let s) = model.phase else { Issue.record("not loaded: \(model.phase)"); return }
        #expect(s.splits.count == 7)
        #expect(model.title == "Morning run")
    }

    @Test @MainActor func modelWithoutTheRouteIsUnavailable() async {
        let none = ActivityDetailModel(activity: Self.activity, provider: nil)
        await none.load()
        #expect(none.phase == .unavailable)
        let notFound = ActivityDetailModel(activity: Self.activity, provider: FakeSeries(result: .failure(HubError.http(status: 404, detail: nil))))
        await notFound.load()
        #expect(notFound.phase == .unavailable)
        let down = ActivityDetailModel(activity: Self.activity, provider: FakeSeries(result: .failure(URLError(.notConnectedToInternet))))
        await down.load()
        guard case .error(let m) = down.phase else { Issue.record("expected error"); return }
        #expect(!m.contains("URLError"))
    }

    @Test func completedWorkoutRowOpensTheDetailFromTraining() throws {
        let row = try source("Training/CompletedWorkoutRow.swift")
        #expect(row.contains("openActivityDetail"))
        let view = try source("Training/TrainingView.swift")
        #expect(view.contains("ActivityDetailView(model:"))
        #expect(view.contains(".environment(\\.openActivityDetail"))
        let registry = try source("Gallery/ScreenRegistry.swift")
        #expect(registry.contains("ScreenEntry(name: \"Activity detail\")"))
    }

    static let activity = DayActivity(activityId: 23926763203, type: "running", name: "Morning run", durationSec: 4800, distanceM: 6694)

    private func source(_ rel: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JIFeatures/\(rel)"), encoding: .utf8)
    }
}

private nonisolated final class FakeSeries: ActivitySeriesProviding, @unchecked Sendable { // @unchecked: one test actor
    let result: Result<ActivitySeries, any Error>
    init(result: Result<ActivitySeries, any Error>) { self.result = result }
    func activitySeries(activityId: Int) async throws -> ActivitySeries { try result.get() }
}
