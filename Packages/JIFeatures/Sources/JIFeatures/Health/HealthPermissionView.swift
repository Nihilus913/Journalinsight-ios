import SwiftUI
import JICore
import JIDesign
import JIHealthKit

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

// MARK: - B-57 W1 r4 board layout (fixer g3, board 5/09)

/// One row of the board's "JI WILL READ" list.
nonisolated struct HealthReadRow: Sendable, Equatable, Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: JIColorRole
    let status: BoardStatus
    var id: String { title }
}

/// What JI reads from Apple Health and whether it can. HealthKit never confirms a read grant, so
/// "Read" means access was answered (JI then sees data after the first sync). Workouts are on the
/// board but no read path ships yet, so that row says so instead of claiming it.
nonisolated func healthReadRows(permission: HKPermission, capabilities: DataCapability) -> [HealthReadRow] {
    let status: BoardStatus = switch permission {
    case .granted: BoardStatus(word: "Read", systemImage: "checkmark", role: .go)
    case .denied: BoardStatus(word: "Declined", systemImage: "exclamationmark.triangle", role: .danger)
    case .notDetermined: BoardStatus(word: "Not asked", systemImage: "minus", role: .muted)
    }
    let hrvSubtitle = capabilities.contains(.hrvRMSSD) ? "RMSSD, the gate signal" : "SDNN until RMSSD is in Health"
    return [
        HealthReadRow(title: "Overnight HRV", subtitle: hrvSubtitle, systemImage: "waveform.path", tint: .reduced, status: status),
        HealthReadRow(title: "Sleep", subtitle: "Duration and stages", systemImage: "moon", tint: .info, status: status),
        HealthReadRow(title: "Resting HR", subtitle: "Overnight only", systemImage: "heart", tint: .danger, status: status),
        HealthReadRow(title: "Workouts", subtitle: "Feeds training load", systemImage: "dumbbell", tint: .muted,
                      status: BoardStatus(word: "Not read yet", systemImage: "minus", role: .muted)),
    ]
}

/// The board's "Connect Apple Health" layout as `List` sections: header (icon, why), the
/// "JI will read" list, "Not on this source" tiles, and the CTA — wired to the existing HealthKit
/// authorisation request (`HealthPermissionViewModel.connect()`).
public struct HealthPermissionBoardSections: View {
    @Environment(\.jiTheme) private var theme
    let model: HealthPermissionViewModel
    /// true = draw the big "Connect Apple Health" title inside the list (the standalone screen).
    var showsTitle: Bool = true

    public init(model: HealthPermissionViewModel, showsTitle: Bool = true) {
        self.model = model
        self.showsTitle = showsTitle
    }

    private static let garminOnly: [(capability: DataCapability, label: String)] = [
        (.bodyBattery, "Body Battery"), (.garminSleepScore, "Sleep score"), (.trainingReadiness, "Readiness"),
    ]

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "heart")
                    .font(.title2)
                    .foregroundStyle(theme.color(.danger))
                    .frame(width: 48, height: 48)
                    .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous))
                    .accessibilityHidden(true)
                if showsTitle {
                    Text("Connect Apple Health").jiFont(.title, weight: .heavy, tint: .text).accessibilityAddTraits(.isHeader)
                }
                Text("Your Watch nights decide Full, Modified or Rest.").jiFont(.body, tint: .muted)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
        }

        Section("JI will read") {
            ForEach(healthReadRows(permission: model.permission, capabilities: model.appleWatchCapabilities)) { row in
                SettingsLinkLabel(title: row.title, subtitle: row.subtitle, systemImage: row.systemImage,
                                  badge: row.status, tint: theme.color(row.tint))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("health.read.\(row.title)")
            }
        }

        let gated = Self.garminOnly.filter { model.isGated($0.capability) }
        if !gated.isEmpty {
            Section("Not on this source") {
                Columns(minimum: 96, spacing: 10) {
                    ForEach(gated, id: \.capability.rawValue) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.label).jiFont(.subheadline, tint: .text)
                            Text("—").jiFont(.statValue, weight: .bold, tint: .muted)
                            Text("Garmin only").jiFont(.footnote, weight: .semibold, tint: .muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(entry.label): no value, Garmin only")
                    }
                }
            }
        }

        Section {
            Button { Task { await model.connect() } } label: {
                Text(model.permission == .granted ? "Apple Health connected" : "Connect Apple Health")
                    .jiFont(.cardTitle, weight: .bold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.color(.info))
            .disabled(model.permission == .granted)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("health-connect")
            .accessibilityHint("Asks iOS for permission to read Apple Health data.")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if model.permission != .notDetermined {
                    Text(HealthPermissionViewModel.statusCopy(for: model.permission))
                        .accessibilityIdentifier("health-permission-status")
                }
                Text("iOS asks next. You can change it in Settings › Health.")
            }
        }
    }
}

/// The standalone board screen (registry entry "Health permission").
public struct HealthPermissionScreen: View {
    let model: HealthPermissionViewModel
    public init(model: HealthPermissionViewModel) { self.model = model }
    public var body: some View {
        List { HealthPermissionBoardSections(model: model) }
            .jiNativeFormChrome()
            .jiTheme(.native)
    }
}
