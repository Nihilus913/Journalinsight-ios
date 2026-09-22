import SwiftUI
import JIDesign
import JIHub

// W5a-L0: `ConnectionSheet`'s "HealthTraining hub" + test sections, moved (not rewritten) into
// the registry. `ConnectionSheet.swift` keeps its own copy as the pre-connection sheet the Today
// error card presents. RN `settings.tsx` "Connection" card: URL, token, Test connection, status,
// "Save & use hub", saved line.
public struct HubSection: SettingsSection {
    public static let sectionId = "l0.hub"
    public let id = Self.sectionId
    public let title = SettingsGroup.connection.title
    public let systemImage = "server.rack"
    public let sortKey = SettingsSortKey.connection
    public let group = SettingsGroupId.sync
    public init() {}
    public var body: some View { HubSectionRows() }
}

private struct HubSectionRows: View {
    @Environment(\.jiTheme) private var theme
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        @Bindable var connection = model.connection
        Section(SettingsGroup.connection.title) {
            TextField("Base URL", text: $connection.baseURL).iosURLField().autocorrectionDisabled()
                .accessibilityLabel("Base URL")
                .accessibilityIdentifier("settings.hub.baseURL")
            SecureField("API token", text: $connection.token)
                .accessibilityLabel("API token")
                .accessibilityIdentifier("settings.hub.token")
        }
        Section {
            Button {
                Task { await model.connection.test() }
            } label: {
                HStack { Text("Test connection"); if model.connection.testing { Spacer(); ProgressView() } }
            }
            .disabled(model.connection.testing)
            .accessibilityLabel("Test connection")
            .accessibilityIdentifier("settings.hub.test")
            if let s = model.connection.status {
                Text(statusText(s)).font(.footnote).foregroundStyle(statusColor(s))
            }
            Button("Save & use hub") { model.saveHub() }
                .tint(theme.color(.info))
                .accessibilityLabel("Save and use hub")
                .accessibilityIdentifier("settings.hub.save")
            if let e = model.connection.saveError { Text(e).font(.footnote).foregroundStyle(theme.color(.danger)) }
            if let saved = model.savedMessage { Text(saved).font(.footnote).foregroundStyle(theme.color(.muted)) }
        }
    }

    // Never interpolate the model or the config here — only the fixed, tokenless strings (rule 2).
    private func statusText(_ s: ConnectionTestResult) -> String {
        switch s {
        case .ok(let last): "Connected. Last sync: \(last ?? "never")."
        case .unauthorized: "Reachable, but the token was rejected (401)."
        case .unreachable(let m): "Unreachable: \(m)"
        case .other(let m): m
        }
    }

    /// RN `resultLabel`: ok → accent (green is the status colour, rule 6), 401/unreachable →
    /// danger, other → warn.
    private func statusColor(_ s: ConnectionTestResult) -> Color {
        switch s {
        case .ok: theme.color(.go)
        case .unauthorized, .unreachable: theme.color(.danger)
        case .other: theme.color(.reduced)
        }
    }
}

// Same iOS-only guard as `ConnectionSheet.swift` (controller ruling 2): `.keyboardType` and
// `.textInputAutocapitalization` don't compile for the macOS host `swift test` builds against.
private extension View {
    @ViewBuilder func iosURLField() -> some View {
        #if os(iOS)
        self.keyboardType(.URL).textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
