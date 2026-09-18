import Foundation
import SwiftUI
import Testing
import JIHub
import JIPersistence
@testable import JIFeatures

// W5a-L0 (P-settings seam), mirrors `mobile/__tests__/settings/settingsScreen.render.test.tsx`
// ("all four sections carry their own SectionLabel", "shows a Backup & restore row", "My KPIs
// row … 7 selected"). `swift test` runs on the macOS host with no SwiftUI renderer, so "renders"
// is asserted on the one thing `SettingsView`'s body iterates — `SettingsViewModel.sections`.

/// The fake a later lane would write: one file, one type, one registry line.
private struct FakeSection: SettingsSection {
    let id = "test.fake"
    let title = "Fake"
    let systemImage = "testtube.2"
    let sortKey = SettingsSortKey.preferences + 50
    var body: some View { Section("Fake") { Text("fake row") } }
}

@MainActor
private func makeModel(sections: [any SettingsSection] = SettingsRegistry.sections,
                       onSaved: @escaping (ConnectionConfig) -> Void = { _ in }) throws -> SettingsViewModel {
    let db = try AppDatabase.inMemory()
    return SettingsViewModel(
        store: ConnectionConfigStore(secrets: InMemorySecretStore()),
        prefs: PrefStore(db: db),
        sections: sections,
        onSaved: onSaved
    )
}

@Test @MainActor func settingsRegistryCarriesTheL0Sections() throws {
    let ids = SettingsRegistry.sections.map(\.id)
    #expect(ids.contains(HubSection.sectionId))
    #expect(ids.contains(HealthSection.sectionId))
    #expect(ids.contains(PreferencesLinksSection.sectionId))
    #expect(ids.contains(DataLinksSection.sectionId))
    #expect(Set(ids).count == ids.count, "section ids must be unique")
}

@Test @MainActor func settingsViewModelRendersEveryRegisteredSectionIncludingAFakeOne() throws {
    let m = try makeModel(sections: SettingsRegistry.sections + [FakeSection()])
    let ids = m.sections.map(\.id)
    #expect(ids.contains("test.fake"))
    for registered in SettingsRegistry.sections { #expect(ids.contains(registered.id)) }
    #expect(ids.count == SettingsRegistry.sections.count + 1)
}

/// RN order: Connection → Preferences → Data → Advanced. A section's place is its `sortKey`
/// alone, never its registry position — the fake (preferences + 50) must land after the built-in
/// Preferences links and before the Data links even though it was appended last.
@Test @MainActor func settingsViewModelOrdersSectionsBySortKeyNotRegistryPosition() throws {
    let m = try makeModel(sections: [FakeSection()] + SettingsRegistry.sections)
    let ids = m.sections.map(\.id)
    let hub = try #require(ids.firstIndex(of: HubSection.sectionId))
    let health = try #require(ids.firstIndex(of: HealthSection.sectionId))
    let prefs = try #require(ids.firstIndex(of: PreferencesLinksSection.sectionId))
    let fake = try #require(ids.firstIndex(of: "test.fake"))
    let data = try #require(ids.firstIndex(of: DataLinksSection.sectionId))
    #expect(hub < health)
    #expect(health < prefs)
    #expect(prefs < fake)
    #expect(fake < data)
    #expect(m.sections.map(\.sortKey) == m.sections.map(\.sortKey).sorted())
}

@Test func settingsGroupBandsFollowTheRNSectionLabels() {
    #expect(SettingsGroup(sortKey: SettingsSortKey.connection) == .connection)
    #expect(SettingsGroup(sortKey: SettingsSortKey.preferences) == .preferences)
    #expect(SettingsGroup(sortKey: SettingsSortKey.preferences + 99) == .preferences)
    #expect(SettingsGroup(sortKey: SettingsSortKey.data) == .data)
    #expect(SettingsGroup(sortKey: SettingsSortKey.advanced + 500) == .advanced)
    #expect(SettingsGroup.connection.title == "Connection")
    #expect(SettingsGroup.preferences.title == "Preferences")
    #expect(SettingsGroup.data.title == "Data")
    #expect(SettingsGroup.advanced.title == "Advanced")
}

@Test @MainActor func settingsViewModelSaveHubForwardsTheSavedConfigAndReportsIt() throws {
    var received: ConnectionConfig?
    let m = try makeModel { received = $0 }
    m.connection.baseURL = "not a url"; m.connection.token = ""
    #expect(m.saveHub() == false)
    #expect(received == nil)
    #expect(m.savedMessage == nil)
    #expect(m.connection.saveError != nil)

    m.connection.baseURL = "http://192.168.1.158:8000"; m.connection.token = "abc"
    #expect(m.saveHub() == true)
    #expect(received?.baseURL.absoluteString == "http://192.168.1.158:8000")
    // RN L320: `setSaved("Using hub — saved.")` — the token never appears here (rule 2).
    #expect(m.savedMessage == "Using hub — saved.")
    #expect(m.savedMessage?.contains("abc") == false)
}

/// RN "My KPIs" subtitle: "7 selected · Today's stat strip and home-screen widget" with the
/// default selection; a persisted selection changes the count.
@Test @MainActor func settingsViewModelKpiSelectedCountReadsTheSharedPrefKey() throws {
    let m = try makeModel()
    #expect(m.kpiSelectedCount == 7)
    #expect(m.kpiSubtitle == "7 selected · Today's stat strip and home-screen widget")
    var prefs = KpiSelection.defaultPrefs()
    prefs.hidden.append(.hrv)
    try m.prefs.set(KpiSelection.prefKey, prefs)
    #expect(m.kpiSelectedCount == 6)
}

/// Optional models default to nil (previews / not unlocked yet) — the rows still exist but
/// explain themselves rather than vanish (CLAUDE.md rule 5).
@Test @MainActor func settingsViewModelOptionalModelsDefaultToNil() throws {
    let m = try makeModel()
    #expect(m.backupModel == nil)
    #expect(m.goalsSetupModel == nil)
    #expect(m.kpiListModel == nil)
    #expect(m.backloadModel == nil)
    #expect(m.healthPermissionModel == nil)
}
