import Foundation
import Observation
import JICore

/// Drives the HealthKit backload (W2h, B-9) from Settings. Built against the frozen
/// `BackloadRunning` protocol only — JIFeatures never imports JIHealthKit (see the wave card);
/// `AppEnvironment` injects the real `HealthKitBackloader`, tests inject a fake runner.
@Observable @MainActor
public final class HealthBackloadViewModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case authorizing
        case running(monthIndex: Int, monthCount: Int, written: Int, skipped: Int)
        case done(BackloadSummary)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    /// W8-L4: DESIGN-7 `ScreenState` over the run `phase` — `authorizing`/`running` are the
    /// loading spell, `done` is loaded, `failed` carries the writer's message. Not hub-backed
    /// (no `HubError`), so `lastError` is always nil here.
    public var screenState: ScreenState {
        ScreenState.resolve(phase: mappedPhase, neverSynced: false, verdictDate: nil, todayDateString: "", lastError: nil)
    }

    private var mappedPhase: TodayViewModel.Phase {
        switch phase {
        case .idle: .idle
        case .authorizing, .running: .loading
        case .done: .loaded
        case .failed(let message): .error(message)
        }
    }

    private let runner: any BackloadRunning
    private let now: () -> Date
    private let hrvPrefs: UserDefaults?
    /// Last day the writer completed, `YYYY-MM-DD` (Zurich) — the same App-Group key
    /// `HealthKitBackloader` persists its resume cursor under. `nil` = never run on this device.
    public private(set) var lastSyncedDay: String?
    private static let cursorKey = "hk.backload.cursor"          // mid-run resume point
    private static let lastCompletedKey = "hk.backload.lastCompletedDay" // set when a run finishes

    /// Default range: hub has Garmin (dso_key = 2) since 2025-05-27 (wave card §Why/what) through today.
    /// `hrvPrefs` is the App-Group suite the writer's cursor lives in (the name is historical —
    /// it used to carry the HRV-as-SDNN toggle, removed with writer v4, B-30); tests inject a
    /// scratch `UserDefaults(suiteName:)`, or `nil` for an unavailable app group — then
    /// `lastSyncedDay` just stays nil and nothing crashes, same contract as `SnapshotStore`.
    public init(
        runner: any BackloadRunning,
        now: @escaping () -> Date = Date.init,
        hrvPrefs: UserDefaults? = UserDefaults(suiteName: "group.toby913.JournalInsight")
    ) {
        self.runner = runner
        self.now = now
        self.hrvPrefs = hrvPrefs
        self.lastSyncedDay = hrvPrefs?.string(forKey: Self.cursorKey) ?? hrvPrefs?.string(forKey: Self.lastCompletedKey)
    }

    /// Re-reads the writer's cursor (called after every progress tick and at the end of a run).
    public func refreshLastSyncedDay() {
        lastSyncedDay = hrvPrefs?.string(forKey: Self.cursorKey) ?? hrvPrefs?.string(forKey: Self.lastCompletedKey)
    }

    public var defaultRange: BackloadRange {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        let from = cal.date(from: DateComponents(year: 2025, month: 5, day: 27)) ?? now()
        return BackloadRange(from: from, to: now())
    }

    public var isRunning: Bool {
        switch phase {
        case .authorizing, .running: true
        default: false
        }
    }

    public func start() async {
        phase = .authorizing
        do {
            try await runner.authorize()
        } catch let error as BackloadError {
            phase = .failed(Self.describe(error))
            return
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        await run(defaultRange)
    }

    private func run(_ range: BackloadRange) async {
        do {
            let summary = try await runner.run(range) { [weak self] progress in
                // `BackloadRunning.run` calls this synchronously on its own caller's task (see
                // JICore's contract doc); every conforming runner (fake or real) invokes it from
                // the same MainActor task that awaited `run`, so this is safe despite the
                // `@Sendable` signature required by the frozen protocol.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.phase = .running(
                        monthIndex: progress.monthIndex,
                        monthCount: progress.monthCount,
                        written: progress.written,
                        skipped: progress.skipped
                    )
                    self.refreshLastSyncedDay()
                }
            }
            phase = .done(summary)
            refreshLastSyncedDay()
        } catch let error as BackloadError {
            phase = .failed(Self.describe(error))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private static func describe(_ error: BackloadError) -> String {
        switch error {
        case .healthDataUnavailable: "Health data isn't available on this device."
        case .authorizationDenied: "Health access was denied. Enable it in Settings > Health > Data Access."
        case .hub(let message): "Hub error: \(message)"
        }
    }
}
