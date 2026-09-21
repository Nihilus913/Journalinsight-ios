import SwiftUI
import JICore
import JIDesign

/// Permission UX + T2-gated tiles for the HealthKit read path (W2d, L3). Renders each of
/// `HKPermission`'s three states with honest copy, and gates the Garmin/Firstbeat-only tiles
/// (Body Battery, Garmin sleep score, training readiness, pre-iOS-27 HRV RMSSD) that Apple
/// Watch can't supply, via the shared `EAGatedTile` idiom (rule 5: never a bare zero).
public struct HealthPermissionView: View {
    @Environment(\.jiTheme) private var theme
    let model: HealthPermissionViewModel

    /// The Garmin/Firstbeat-only metrics that never come from Apple Watch, or (RMSSD) only on
    /// iOS 27+ — checked against `model.appleWatchCapabilities` (the T2 set).
    private static let sourceGatedCapabilities: [(capability: DataCapability, label: String)] = [
        (.bodyBattery, "Body Battery"),
        (.garminSleepScore, "Sleep score"),
        (.trainingReadiness, "Training readiness"),
        (.hrvRMSSD, "HRV (RMSSD)"),
    ]

    public init(model: HealthPermissionViewModel) {
        self.model = model
    }

    public var body: some View {
        // Rendered inside the caller's `List` section (Settings › Connection), so these are
        // plain rows — the section's own header/footer is the caller's (§2b.2).
        Group {
            statusText
            Button("Connect Apple Health") { Task { await model.connect() } }
                .disabled(model.permission == .granted)
                .accessibilityIdentifier("health-connect")
                .accessibilityHint("Asks iOS for permission to read Apple Health data.")

            // §8.1: the gated tiles reflow 2-up instead of stacking one per line.
            Columns(minimum: 160) {
                ForEach(Self.sourceGatedCapabilities, id: \.capability.rawValue) { entry in
                    if model.isGated(entry.capability) {
                        EAGatedTile(label: entry.label, reason: "Not available on this source")
                    }
                }
            }
        }
    }

    private var statusText: some View {
        Text(HealthPermissionViewModel.statusCopy(for: model.permission))
            .jiFont(.footnote)
            .foregroundStyle(model.permission == .granted ? theme.color(.go) : theme.color(.muted))
            .accessibilityIdentifier("health-permission-status")
    }
}
