import Testing
@testable import JIFeatures

// W-GUI M5 — Settings (41) + Sync & hub (43): the root keeps its groups and the hub / health rows.
@Test func settingsRootKeepsHubAndHealthRows() {
    let ids = SettingsRoot.rows.map(\.id)
    #expect(ids.contains("hub") && ids.contains("health"))
    #expect(SettingsRoot.rows.contains { if case .syncNow = $0.kind { return true } else { return false } })
    #expect(!settingsSyncTrailing(syncing: true, failed: false, lastSync: nil, now: .init()).isEmpty)
}
