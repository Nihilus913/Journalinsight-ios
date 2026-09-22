import SwiftUI
import JIDesign

// W5a-L0: `ConnectionSheet`'s Health sections (W2h backload, W2d Apple Watch read), moved (not
// rewritten) into the registry. Both models are optional on `SettingsViewModel` — nil hides the
// matching section exactly as `ConnectionSheet` does (previews / no HealthKit path wired).
public struct HealthSection: SettingsSection {
    public static let sectionId = "l0.health"
    public let id = Self.sectionId
    public let title = "Apple Health"
    public let systemImage = "heart.text.square"
    public let sortKey = SettingsSortKey.connection + 10
    public let group = SettingsGroupId.health
    public init() {}
    public var body: some View { HealthSectionRows() }
}

private struct HealthSectionRows: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        if let backloadModel = model.backloadModel {
            HealthBackloadSection(model: backloadModel)
        }
        if let healthPermissionModel = model.healthPermissionModel {
            Section("Apple Watch (read)") {
                HealthPermissionView(model: healthPermissionModel)
            }
        }
    }
}
