import Foundation
import SwiftUI
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

/// W-OFFLINE2 OFF2-4: the no-hub Training tab (needs-hub line + the Apple Health workouts) as an
/// ImageRenderer shot — the seeded erased-clone E2E is the merger's (needs off2-l2's seed). PNG to
/// `OFF2_SHOTS` (TEST_RUNNER_OFF2_SHOTS) when set; the model + render are asserted either way.
@Suite @MainActor struct TrainingHistoryListShotTests {
    struct FakeHistory: TrainingProviding, TrainingHistoryProviding, ActivitySeriesProviding {
        let rows: [DayActivity]
        func recentWorkouts(days: Int) async throws -> [DayActivity] { rows }
        func activitySeries(activityId: Int) async throws -> ActivitySeries { throw NeedsHubError() }
        func trainingDay(date: String) async throws -> TrainingDayDetail { throw NeedsHubError() }
        func exercises() async throws -> [Exercise] { throw NeedsHubError() }
        func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult { throw NeedsHubError() }
    }

    static let rows: [DayActivity] = [
        DayActivity(activityId: -5, type: "running", name: nil, durationSec: 2_400, distanceM: 7_200, source: "apple", avgHr: 151, startTimeUtc: "2026-10-06T05:00:00Z"),
        DayActivity(activityId: -4, type: "walking", name: nil, durationSec: 1_800, distanceM: 2_400, source: "apple", startTimeUtc: "2026-10-05T10:00:00Z"),
        DayActivity(activityId: -3, type: "traditional_strength_training", name: nil, durationSec: 3_300, distanceM: nil, source: "apple", avgHr: 118, startTimeUtc: "2026-10-04T16:00:00Z"),
        DayActivity(activityId: -2, type: "running", name: nil, durationSec: 3_900, distanceM: 12_000, source: "apple", avgHr: 148, startTimeUtc: "2026-10-02T05:00:00Z"),
        DayActivity(activityId: -1, type: "walking", name: nil, durationSec: 2_700, distanceM: 3_600, source: "apple", startTimeUtc: "2026-10-01T15:00:00Z"),
    ]

    @Test func noHubTrainingShowsTheHealthKitHistory() async throws {
        let model = TrainingViewModel(provider: FakeHistory(rows: Self.rows), healthProvider: NeedsHubProvider(),
                                      cache: OfflineCache(db: try AppDatabase.inMemory()), availability: .needsHub)
        await model.load()
        #expect(model.phase == .error(NeedsHubCopy.training))
        #expect(model.hasOnDeviceHistory && model.historyWorkouts.count == 5)
        #expect(model.historyWorkouts.map(model.historyRowIsTappable) == [true, false, true, true, false])

        let view = VStack(alignment: .leading, spacing: 16) {
            Surface { Text(NeedsHubCopy.training) }
            TrainingHistoryList(workouts: model.historyWorkouts, loaded: model.historyLoaded,
                                isTappable: model.historyRowIsTappable, open: { _ in })
        }
        .padding(16).jiTheme(.native).environment(\.jiOffscreenRender, true)
        .frame(width: 402).background(Color(white: 0.95))
        let r = ImageRenderer(content: view)
        r.scale = 3
        let png = try #require(r.uiImage?.pngData())
        if let dir = ProcessInfo.processInfo.environment["OFF2_SHOTS"], !dir.isEmpty {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("off2-4-training-history-nohub.png"))
        }
    }

    @Test func withAHubTheHistoryIsNotShown() async throws {
        let model = TrainingViewModel(provider: FakeHistory(rows: Self.rows), healthProvider: NeedsHubProvider(),
                                      cache: OfflineCache(db: try AppDatabase.inMemory()))
        #expect(!model.hasOnDeviceHistory)
    }
}
