import Foundation
import JICore
import JIFeatures
#if canImport(HealthKit)
import HealthKit
import JIHealthKit
#endif
import JIPersistence

/// W-OFFLINE OFF-1 (B-50 slice 1): the hub-only screens' models (Training, Energy, Nutrition,
/// Goals setup, Progression) are ALWAYS built. `source` is `RootTabView.hubScreensSource(...)`
/// (nil = no hub configured). When it does not speak the screen's `<Screen>Providing` protocol
/// (no hub, or the on-device `HealthKitProvider`), the model gets `NeedsHubProvider` and
/// `.needsHub`: the OfflineCache copy if any, else "Connect the hub in Settings to see …" —
/// never a nil model (blank tab / "unavailable") or a spinner waiting on a hub that isn't there.
@MainActor
enum HubScreensFallback {
    static func energy(source: (any HealthDataProvider)?, cache: OfflineCache, now: @escaping () -> Date = Date.init,
                       band: EnergyBandService? = nil) -> EnergyViewModel {
        if let p = source as? any EnergyProviding {
            return EnergyViewModel(provider: p, cache: cache, now: now, band: band)
        }
        return EnergyViewModel(provider: NeedsHubProvider(), cache: cache, now: now, band: band, availability: .needsHub)
    }

    static func nutrition(source: (any HealthDataProvider)?, cache: OfflineCache,
                          now: @escaping () -> Date = Date.init) -> NutritionViewModel {
        if let p = source as? any NutritionProviding {
            return NutritionViewModel(provider: p, cache: cache, now: now)
        }
        return NutritionViewModel(provider: NeedsHubProvider(), cache: cache, now: now, availability: .needsHub)
    }

    /// `healthProvider` = the tiles' data source (nil = no connection at all).
    /// W-OFFLINE2 OFF2-4: `history` = the on-device completed workouts (HealthKit) the no-hub
    /// Training tab lists; ignored when a hub serves Training (hub behaviour unchanged).
    static func training(source: (any HealthDataProvider)?, healthProvider: (any HealthDataProvider)?, cache: OfflineCache,
                         outbox: Outbox? = nil, drainer: OutboxDrainer? = nil,
                         history: (any TrainingHistoryProviding & ActivitySeriesProviding)? = OnDeviceTrainingProvider.liveHistory(),
                         now: @escaping () -> Date = Date.init) -> TrainingViewModel {
        if let p = source as? any TrainingProviding {
            return TrainingViewModel(provider: p, healthProvider: healthProvider ?? NeedsHubProvider(), cache: cache,
                                     outbox: outbox, drainer: drainer, now: now)
        }
        // No hub: no hub write queue either (a weekday assignment has nowhere to go).
        let provider: any TrainingProviding = history.map { OnDeviceTrainingProvider(history: $0) } ?? NeedsHubProvider()
        return TrainingViewModel(provider: provider, healthProvider: healthProvider ?? NeedsHubProvider(),
                                 cache: cache, now: now, availability: .needsHub)
    }

    /// `make` = the shell's own builder (`RootTabView.makeGoalsSetup`), so the local-first saves
    /// (macros, targets) keep their wiring with or without a hub.
    static func goalsSetup(source: (any HealthDataProvider)?,
                           make: (any GoalsSetupProviding, HubAvailability) -> GoalsSetupViewModel) -> GoalsSetupViewModel {
        if let p = source as? any GoalsSetupProviding { return make(p, .live) }
        return make(NeedsHubProvider(), .needsHub)
    }

    static func progression(source: (any HealthDataProvider)?, cache: OfflineCache, prefs: PrefStore?) -> ProgressionService {
        ProgressionService(provider: source as? any TrainingProviding, cache: cache, prefs: prefs)
    }
}

/// W-OFFLINE2 OFF2-4 (B-50 slice 2): the no-hub Training tab's `TrainingProviding` subset —
/// history only. The completed workouts and their HR-only Activity detail come from HealthKit
/// (`HKTrainingHistoryReader`); every plan / progression / assignment read or write still throws
/// `NeedsHubError` (slice 1), and so does the day detail, so no HealthKit row is ever cached under
/// a hub key (`training.day.<date>`) that a later hub connection would read as the hub's.
nonisolated struct OnDeviceTrainingProvider: TrainingProviding, TrainingHistoryProviding, ActivitySeriesProviding {
    let history: any TrainingHistoryProviding & ActivitySeriesProviding

    func recentWorkouts(days: Int) async throws -> [DayActivity] { try await history.recentWorkouts(days: days) }
    func activitySeries(activityId: Int) async throws -> ActivitySeries {
        do { return try await history.activitySeries(activityId: activityId) } catch {
            throw HubError.http(status: 404, detail: nil)   // "no recorded series" — the detail's unavailable state
        }
    }

    func trainingDay(date: String) async throws -> TrainingDayDetail { throw NeedsHubError() }
    func exercises() async throws -> [Exercise] { throw NeedsHubError() }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult { throw NeedsHubError() }
    func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut { throw NeedsHubError() }
    func planSessions() async throws -> [PlanSessionOut] { throw NeedsHubError() }
    func planWeek(start: String) async throws -> PlanWeekOut { throw NeedsHubError() }

    /// The real HealthKit history; nil without Health data, under XCTest, or with `-no-healthkit`.
    @MainActor static func liveHistory() -> (any TrainingHistoryProviding & ActivitySeriesProviding)? {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(),
              AppEnvironment.readsHealthWorkouts(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
        else { return nil }
        let reader = RealHealthStoreReader()
        return HKTrainingHistoryReader(store: reader, heartRate: reader)
        #else
        return nil
        #endif
    }
}
