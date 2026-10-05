import SwiftUI
import JIDesign
import JIPersistence

/// W-ONDEVICE O-10: the dual-run line on the Developer screen — "parity N days, M diffs".
/// `days` counts mornings with both verdicts; mornings without a hub verdict are named separately
/// and never counted as a match.
public nonisolated func onDeviceParityLine(_ parity: ShadowParity) -> String {
    var line = "parity \(parity.days) day\(parity.days == 1 ? "" : "s"), \(parity.diffs) diff\(parity.diffs == 1 ? "" : "s")"
    if parity.hubMissing > 0 { line += " · \(parity.hubMissing) without hub" }
    return line
}

/// O-11's measurement row: the morning, both verdict classes, and wake -> verdict latency.
public nonisolated func onDeviceShadowRowLine(_ row: ShadowVerdictRow) -> String {
    let hub = row.hubVerdict.map(ShadowParity.verdictClass) ?? "—"
    let latency = row.latencyFromWakeSec.map { "\(Int(($0 / 60).rounded())) min after wake" } ?? "wake unknown"
    return "\(row.day) · \(ShadowParity.verdictClass(row.onDeviceVerdict)) vs hub \(hub) · \(latency)"
}

/// W-FIX-P2 RG-53 (B-44od): the Developer copy for the verdict source — since 2026-10-05 the
/// phone computes the verdict the gate and Decide show; the hub keeps computing as the oracle.
public nonisolated enum DeveloperVerdictCopy {
    public static let gateNote = "Today's verdict and gate are computed on this iPhone. The hub keeps computing the same morning as the oracle; both are compared in the database."
    public static let onDeviceToggleSubtitle = "Verdict computed on this iPhone · hub = oracle · takes effect at next launch"
}

/// The Developer screen's current on-device estimate ("Estimate — calibrating (N/28 nights) ·
/// GO — …"). The App binds `load` at launch when the on-device verdict is enabled (DEBUG only);
/// nil = the line is not shown.
public enum OnDeviceVerdictPreview {
    public static var load: (@Sendable () async -> String)?
}

/// W-ONDEVICE O-9/O-10: the DEBUG-only on-device verdict switch + the dual-run log. Not compiled
/// into Release (NO release switch this wave: Release stays `.hub`).
#if DEBUG
public struct OnDeviceVerdictSection: SettingsSection {
    public static let sectionId = "ondevice.verdict"
    /// Read by `App/Notifications/OnDeviceVerdictWiring` at launch.
    public static let enabledKey = "ji.ondevice.verdict.enabled"
    public let id = Self.sectionId
    public let title = "On-device verdict"
    public let systemImage = "iphone.gen3"
    public let sortKey = SettingsSortKey.connection + 61
    public let group = SettingsGroupId.developer
    public init() {}

    public var body: some View { OnDeviceVerdictRows() }
}

private struct OnDeviceVerdictRows: View {
    @Environment(\.jiTheme) private var theme
    @AppStorage(OnDeviceVerdictSection.enabledKey) private var enabled = false
    @State private var parity: ShadowParity?
    @State private var rows: [ShadowVerdictRow] = []
    @State private var estimate: String?

    var body: some View {
        Section("On-device verdict (debug)") {
            Toggle(isOn: $enabled) {
                SettingsLinkLabel(title: "Compute the verdict on this iPhone",
                                  subtitle: DeveloperVerdictCopy.onDeviceToggleSubtitle)
            }
            .tint(theme.color(.info))
            .accessibilityIdentifier("settings.toggle.ondevice.verdict")

            if let estimate {
                Text(estimate)
                    .font(.subheadline)
                    .accessibilityIdentifier("settings.ondevice.estimate")
            }
            Text(parity.map(onDeviceParityLine) ?? "No on-device mornings logged yet")
                .font(.subheadline)
                .accessibilityIdentifier("settings.ondevice.parity")
            ForEach(rows, id: \.day) { row in
                Text(onDeviceShadowRowLine(row))
                    .font(.caption)
                    .foregroundStyle(theme.color(.muted))
            }
        }
        .task {
            if let load = OnDeviceVerdictPreview.load { estimate = await load() }
            guard let db = try? AppDatabase.onDisk() else { return }
            let store = DecisionLogStore(db: db)
            parity = try? store.shadowParity()
            rows = (try? store.shadowRows(limit: 7)) ?? []
        }
    }
}
#endif
