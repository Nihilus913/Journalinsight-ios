import Foundation
import HealthKit
import JICore
import JIFeatures
import JIHealthKit
import JIPersistence

/// W7-L3 (P-healthkit-t2-provider): the only place in the app that knows both concrete providers.
///
/// `JIFeatures` must never import `JIHealthKit` (the Settings UI is built against protocols and
/// view models only — see `AppEnvironment.makeHealthPermissionModel`'s note), so the debug data-
/// source toggle lives there against `JIFeatures.ProviderSwitch` while this file supplies the two
/// halves it cannot: whether a T2 provider is buildable on this device, and how to build one.
///
/// Both providers are held for the app's lifetime — switching back to the hub must not rebuild a
/// `HubClient` (and re-read the Keychain) just to undo a debug toggle.
@MainActor
enum ProviderSelection {
    /// Wires `ProviderSwitch` to a live `ProviderStore` and applies the persisted choice.
    ///
    /// Called once per `AppEnvironment.apply(_:)`, i.e. on every hub (re)connection, with that
    /// connection's fresh `HubDataProvider` as the T1 half. Re-installing replaces the closure,
    /// so a later toggle always swaps between the CURRENT hub provider and the T2 one.
    /// `using:` is the app-wide `ProviderSwitch.shared` in production and exists so a test can
    /// drive the same wiring against an isolated instance.
    static func install(
        store: ProviderStore,
        hub: any HealthDataProvider,
        prefs: PrefStore,
        using providerSwitch: ProviderSwitch = .shared
    ) {
        let appleWatch = makeAppleWatchProvider()
        providerSwitch.install(prefs: prefs, isAppleWatchAvailable: appleWatch != nil) { kind in
            store.provider = provider(for: kind, hub: hub, appleWatch: appleWatch)
        }
    }

    /// The T2 provider, or `nil` when HealthKit cannot serve this device at all (iPad, Mac, a
    /// simulator without Health) — the toggle then says so instead of switching to a source with
    /// nothing in it (XC `CLAUDE.md` rule 5).
    static func makeAppleWatchProvider() -> HealthKitProvider? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        return HealthKitProvider(store: RealHealthStoreReader())
    }

    static func provider(
        for kind: ProviderKind,
        hub: any HealthDataProvider,
        appleWatch: HealthKitProvider?
    ) -> any HealthDataProvider {
        switch kind {
        case .hub: hub
        // Falling back to the hub rather than failing: `select(.appleWatch)` is already refused
        // when T2 is unavailable, so this branch only ever runs for a stale persisted value.
        case .appleWatch: appleWatch ?? hub
        }
    }
}
