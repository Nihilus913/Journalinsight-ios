import SwiftUI
import JICore
import JIDesign

/// Permission UX + T2-gated tiles for the HealthKit read path (W2d, L3). Renders each of
/// `HKPermission`'s three states with honest copy, and gates the Garmin/Firstbeat-only tiles
/// (Body Battery, Garmin sleep score, training readiness, pre-iOS-27 HRV RMSSD) that Apple
/// Watch can't supply, via the shared `EAGatedTile` idiom (rule 5: never a bare zero).
public struct HealthPermissionView: View {
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
        VStack(alignment: .leading, spacing: 12) {
            statusText
            Button("Connect Apple Health") { Task { await model.connect() } }
                .disabled(model.permission == .granted)
                .accessibilityIdentifier("health-connect")
                .accessibilityHint("Asks iOS for permission to read Apple Health data.")

            ForEach(Self.sourceGatedCapabilities, id: \.capability.rawValue) { entry in
                if model.isGated(entry.capability) {
                    EAGatedTile(label: entry.label, reason: "Not available on this source")
                }
            }
        }
    }

    private var statusText: some View {
        Text(HealthPermissionViewModel.statusCopy(for: model.permission))
            .font(.footnote)
            .foregroundStyle(model.permission == .granted ? JIColor.go : JIColor.muted)
            .accessibilityIdentifier("health-permission-status")
    }
}
