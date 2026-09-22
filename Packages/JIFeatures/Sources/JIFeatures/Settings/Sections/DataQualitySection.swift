import SwiftUI

// W5b-L1 (P-data-quality). RN reaches `/data-quality` from Today's `DataFreshnessBadge` (its real
// entry, wired in `Today/TodayGrid.swift`); this Settings row is the card's second landing on the
// same `DataQualityView`, in the Data band after the L0 Backup & restore link.
public struct DataQualitySection: SettingsSection {
    public static let sectionId = "w5b.l1.dataQuality"
    public let id = Self.sectionId
    public let title = "Data quality"
    public let systemImage = "checkmark.shield"
    public let sortKey = SettingsSortKey.data + 20
    public let group = SettingsGroupId.sync
    public init() {}
    public var body: some View { DataQualitySectionRows() }
}

private struct DataQualitySectionRows: View {
    var body: some View {
        Section {
            NavigationLink {
                // Built at push time, not at row-render time, so the installed provider (and a
                // reconnection that replaced it) is the one the screen reads.
                if let model = DataQualityAccess.shared.makeViewModel() {
                    DataQualityView(model: model)
                } else {
                    DataQualityUnavailableView()
                }
            } label: {
                SettingsLinkLabel(title: "Data quality", subtitle: "Per-source freshness, quality score and trust")
            }
            .accessibilityLabel("Data quality")
            .accessibilityIdentifier("settings.row.dataQuality")
        }
    }
}
