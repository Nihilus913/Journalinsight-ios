import Testing
import JIFeatures
@testable import JournalInsight

// W5a-L0 (P-settings): the gear in `RootTabView` presents `SettingsView`, whose content is the
// registry. `RootTabView`'s body can't be rendered here (needs `AppEnvironment` + a hub), so
// this pins what the app target actually links against: the registry the sheet iterates carries
// the moved hub/health sections and the L0 link rows, in RN's group order.
@Test @MainActor func settingsRegistryVisibleFromTheAppTargetIsInRNGroupOrder() {
    let sections = SettingsRegistry.sections.sorted { $0.sortKey < $1.sortKey }
    let bands = sections.map { SettingsGroup.allCases.firstIndex(of: SettingsGroup(sortKey: $0.sortKey))! }
    #expect(sections.first?.id == HubSection.sectionId)
    #expect(sections.contains { $0.id == HealthSection.sectionId })
    #expect(bands == bands.sorted(), "Connection → Preferences → Data → Advanced")
    #expect(Set(bands).count >= 3, "hub/health, preferences links, data links")
}
