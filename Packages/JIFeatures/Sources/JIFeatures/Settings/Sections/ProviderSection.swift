import SwiftUI
import Observation
import JIDesign
import JIPersistence

/// Which data source the app is reading from (spec §4.2's two tiers).
public nonisolated enum ProviderKind: String, Codable, Sendable, CaseIterable, Equatable {
    /// T1 — the Mac hub (Garmin Fenix depth, the full `DataCapability.hubAll` bitmap).
    case hub
    /// T2 — HealthKit on this device (`JIHealthKit.HealthKitProvider`). The gate/verdict stay OFF
    /// there until the overnight-equivalence proof lands; see that type's doc comment.
    case appleWatch

    public var title: String {
        switch self {
        case .hub: "HealthTraining hub"
        case .appleWatch: "Apple Watch (on device)"
        }
    }
}

/// W7-L3 seam between the Settings UI (JIFeatures, which must never import `JIHealthKit`) and the
/// app, which is the only layer that can build a concrete provider. `App/ProviderSelection.swift`
/// calls `install(...)` once at boot; this section only ever reads `kind` and calls `select(_:)`.
///
/// A single shared instance rather than a `SettingsViewModel` field because that view model is
/// frozen after W5a-L0 (`SettingsViewModel.swift`) — a lane may add a section, never a field.
@Observable @MainActor
public final class ProviderSwitch {
    public static let shared = ProviderSwitch()
    /// `PrefStore` key the choice persists under.
    public static let prefKey = "provider.selection"

    public private(set) var kind: ProviderKind = .hub
    /// False until the app reports that a T2 provider can actually be built on this device.
    public private(set) var isAppleWatchAvailable = false
    /// Bumped once per *effective* provider change — every time `apply` actually runs, i.e. on
    /// `install` (boot and every hub reconnection) and on an accepted `select`, never on a no-op
    /// or a refused one.
    ///
    /// The screens cache their view models (`RootTabView`'s `todayModel`/`recoveryModel`/…), and
    /// each of those captures `store.provider` at init. Swapping `ProviderStore.provider` alone
    /// therefore changed nothing on screen: Today and Recovery kept reading the previous source
    /// until an unrelated reconnect happened to rebuild them. `revision` is the value those caches
    /// key on, so one `.onChange` site drops them and the next render rebuilds against the
    /// provider that is actually active.
    public private(set) var revision = 0

    private var prefs: PrefStore?
    private var apply: ((ProviderKind) -> Void)?

    public init() {}

    /// Wires the seam and applies the persisted choice. Returns the kind that ended up active.
    ///
    /// The default is always the hub, and in a **release** build the persisted value is ignored
    /// outright: T2 is a debug-only capability this wave (the verdict is not equivalent yet), so
    /// a stale pref must never silently downgrade a shipped build's data source.
    @discardableResult
    public func install(
        prefs: PrefStore,
        isAppleWatchAvailable: Bool,
        apply: @escaping (ProviderKind) -> Void
    ) -> ProviderKind {
        self.prefs = prefs
        self.isAppleWatchAvailable = isAppleWatchAvailable
        self.apply = apply
        #if DEBUG
        let stored = try? prefs.get(Self.prefKey, as: ProviderKind.self)
        kind = (stored == .appleWatch && isAppleWatchAvailable) ? .appleWatch : .hub
        #else
        kind = .hub
        #endif
        revision += 1
        apply(kind)
        return kind
    }

    /// Persists and applies a new choice. A no-op when nothing changes, or when T2 was asked for
    /// on a device that cannot supply it (rule 5: never switch to a source that has no data).
    public func select(_ new: ProviderKind) {
        guard new != kind else { return }
        guard new == .hub || isAppleWatchAvailable else { return }
        kind = new
        try? prefs?.set(Self.prefKey, new)
        revision += 1
        apply?(new)
    }
}

/// W7-L3 (P-healthkit-t2-provider): the debug-only data-source switch, in the Connection band
/// next to the hub fields it competes with. Ships as an empty section in release builds — T2 is
/// gated off until the Apple-vs-Garmin overnight-equivalence proof (spec risk table L276).
public struct ProviderSection: SettingsSection {
    public static let sectionId = "l3.provider"
    public let id = Self.sectionId
    public let title = "Data source"
    public let systemImage = "antenna.radiowaves.left.and.right"
    public let sortKey = SettingsSortKey.connection + 60
    public init() {}

    public var body: some View {
        #if DEBUG
        ProviderSectionRows(providerSwitch: ProviderSwitch.shared)
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG
private struct ProviderSectionRows: View {
    @Bindable var providerSwitch: ProviderSwitch

    private var useAppleWatch: Binding<Bool> {
        Binding(
            get: { providerSwitch.kind == .appleWatch },
            set: { providerSwitch.select($0 ? .appleWatch : .hub) }
        )
    }

    var body: some View {
        Section("Data source (debug)") {
            Toggle(isOn: useAppleWatch) {
                SettingsLinkLabel(
                    title: "Read from Apple Watch",
                    subtitle: providerSwitch.isAppleWatchAvailable
                        ? "Recovery is computed on this device from Health instead of the hub"
                        : "Health data isn't available on this device"
                )
            }
            .disabled(!providerSwitch.isAppleWatchAvailable)
            .tint(JIColor.info)
            .accessibilityLabel("Read from Apple Watch")
            .accessibilityIdentifier("settings.toggle.provider.appleWatch")

            Text("Today's verdict and gate stay on the hub — not available on Apple Watch until Apple and Garmin nights are proven equivalent.")
                .font(.caption)
                .foregroundStyle(JIColor.muted)
                .accessibilityIdentifier("settings.row.provider.gateNote")

            Text("Active: \(providerSwitch.kind.title)")
                .font(.caption)
                .foregroundStyle(JIColor.muted)
                .accessibilityIdentifier("settings.row.provider.active")
        }
    }
}
#endif
