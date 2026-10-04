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
    /// Stale-source count for the row's badge (nil until the hub answered — no badge, not "0").
    @State private var stale: Int?

    var body: some View {
        SettingsRowGroup {
            NavigationLink {
                // F-5 (B-59): the screen owns its model (`@State`), so this row's badge update
                // re-rendering the link can no longer swap in an idle model mid-load.
                DataQualityScreen()
            } label: {
                SettingsLinkLabel(title: "Data quality", subtitle: settingsDataSubtitles["Data quality"] ?? "", systemImage: "checkmark.shield",
                                  badge: settingsDataQualityBadge(stale: stale))
            }
            .task {
                guard stale == nil, let model = DataQualityAccess.shared.makeViewModel() else { return }
                await model.load()
                if model.phase == .loaded, !model.sourceSummary.sources.isEmpty { stale = model.sourceSummary.stale }
            }
            .accessibilityLabel("Data quality")
            .accessibilityIdentifier("settings.row.dataQuality")
        }
    }
}
