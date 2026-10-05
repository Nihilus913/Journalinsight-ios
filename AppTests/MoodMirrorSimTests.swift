import Foundation
import HealthKit
import Testing
import JIHealthKit
import JIPersistence
import JIFeatures
@testable import JournalInsight

/// B-24 P3 sim exit: the REAL save path (`MindViewModel.upsertCheckin` -> `HealthKitMoodMirror`
/// -> `StateOfMindWriter` -> `RealHealthStore`) writes into the simulator's HealthKit, and the
/// sample is read back from the store:
/// 1. toggle on (Settings model, real State of Mind auth), save mood=good -> 1 sample, valence 0.5, dailyMood;
/// 2. re-save mood=bad the same day -> still 1 sample (upsert by sync id `mind:<day>`), valence -0.5;
/// 3. toggle off, save mood=great -> no write (still the one -0.5 sample).
///
/// Opt-in. On a fresh sim first grant State of Mind write once through the real Settings toggle
/// (`TEST_RUNNER_JI_B24_GRANT=1 xcodebuild test -scheme AppUITests ... -only-testing:AppUITests/B24HealthGrantUITests`),
/// then run `TEST_RUNNER_JI_B24_SIM=1 xcodebuild test ... -only-testing:JournalInsightTests/MoodMirrorSimTests`.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["JI_B24_SIM"] == "1"))
struct MoodMirrorSimTests {
    private let hk = RealHealthStore()

    private func checkIn(_ mood: JIPersistence.Mood, day: String) -> NewCheckIn {
        NewCheckIn(date: day, mood: mood, stress: 4, energy: 2, dosed: true,
                   irritability: nil, restlessness: nil, appetite: nil, note: "b24 sim private note")
    }

    /// State of Mind samples carrying this day's sync id, read back from the sim's HealthKit.
    private func samples(for day: String) async throws -> [StateOfMindReadBack] {
        let noon = try StateOfMindWriter(store: hk).sampleDate(for: day)
        let all = try await hk.stateOfMindSamples(start: noon.addingTimeInterval(-86_400), end: noon.addingTimeInterval(86_400))
        return all.filter { $0.syncIdentifier == StateOfMindWriter<RealHealthStore>.syncIdentifier(for: day) }
    }

    /// The mirror is fire-and-forget: poll the store (bounded, 10 s) until `want` holds.
    private func awaitSamples(for day: String, _ want: ([StateOfMindReadBack]) -> Bool) async throws -> [StateOfMindReadBack] {
        var got: [StateOfMindReadBack] = []
        for _ in 0..<50 {
            got = try await samples(for: day)
            if want(got) { return got }
            try await Task.sleep(for: .milliseconds(200))
        }
        return got
    }

    @Test(.timeLimit(.minutes(3)))
    func b24_saveCheckin_mirrorsOneStateOfMindSample_upsertAndToggleOff() async throws {
        // No read request: HealthKit lets an app query the samples it saved itself, so the
        // share-only grant (Settings toggle, given once via B24HealthGrantUITests) suffices.
        let suite = "ji.b24.simtest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let mirror = HealthKitMoodMirror(store: hk)
        let settings = MoodMirrorSettingsModel(mirror: mirror, defaults: defaults)
        #expect(settings.enabled == false, "off by default")
        await settings.setEnabled(true)
        #expect(settings.enabled, "State of Mind share auth granted -> toggle on")

        let db = try AppDatabase.inMemory()
        let model = MindViewModel(checkins: CheckInStore(db: db), eventStore: EventStore(db: db), who5Store: Who5Store(db: db),
                                  moodMirror: mirror, mirrorEnabled: { MoodMirrorPrefs.isEnabled(defaults) })
        let day = todayISOString()
        // Clean slate for re-runs: remove any earlier mirror of today.
        try await StateOfMindWriter(store: hk).write(MoodMirrorEntry(date: day, valence: nil, updatedAt: Date()))
        #expect(try await samples(for: day).isEmpty)

        // 1. save mood=good -> one dailyMood sample, valence 0.5.
        #expect(await model.upsertCheckin(checkIn(.good, day: day)))
        var got = try await awaitSamples(for: day) { $0.count == 1 && $0.first?.valence == 0.5 }
        print("[B24-SIM] after good: count=\(got.count) valence=\(got.map(\.valence)) dailyMood=\(got.map(\.isDailyMood)) id=\(got.first?.syncIdentifier ?? "nil")")
        #expect(got.count == 1)
        #expect(got.first?.valence == 0.5)
        #expect(got.first?.isDailyMood == true)

        // 2. re-save mood=bad same day -> still one sample, valence -0.5.
        #expect(await model.upsertCheckin(checkIn(.bad, day: day)))
        got = try await awaitSamples(for: day) { $0.count == 1 && $0.first?.valence == -0.5 }
        print("[B24-SIM] after bad re-save: count=\(got.count) valence=\(got.map(\.valence))")
        #expect(got.count == 1)
        #expect(got.first?.valence == -0.5)

        // 3. toggle off -> a save writes nothing (sample unchanged).
        await settings.setEnabled(false)
        #expect(MoodMirrorPrefs.isEnabled(defaults) == false)
        #expect(await model.upsertCheckin(checkIn(.great, day: day)))
        try await Task.sleep(for: .seconds(2))
        got = try await samples(for: day)
        print("[B24-SIM] after toggle-off save: count=\(got.count) valence=\(got.map(\.valence))")
        #expect(got.count == 1)
        #expect(got.first?.valence == -0.5)
    }
}
