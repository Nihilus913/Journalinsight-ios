import Foundation
import JICore
import JIFeatures
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
    static func training(source: (any HealthDataProvider)?, healthProvider: (any HealthDataProvider)?, cache: OfflineCache,
                         outbox: Outbox? = nil, drainer: OutboxDrainer? = nil,
                         now: @escaping () -> Date = Date.init) -> TrainingViewModel {
        if let p = source as? any TrainingProviding {
            return TrainingViewModel(provider: p, healthProvider: healthProvider ?? NeedsHubProvider(), cache: cache,
                                     outbox: outbox, drainer: drainer, now: now)
        }
        // No hub: no hub write queue either (a weekday assignment has nowhere to go).
        return TrainingViewModel(provider: NeedsHubProvider(), healthProvider: healthProvider ?? NeedsHubProvider(),
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
