import Foundation
import SwiftUI
import Testing
@testable import JIFeatures

// W-B41 L1 (B-41, P-settings). The Settings screen is now a two-level menu: the top level is one
// row per `SettingsGroupId`, each pushing `GroupSettingsView`. These tests pin the contract that
// replaces the flat list — every section lands in exactly one group, every group is reachable,
// and the DEBUG-only Developer group (the data-source switch) never ships.

/// A section that never sets `group` — it must fall back to the sortKey band default, which is
/// what lets a section file be reassigned in its own commit rather than all at once.
private struct UnassignedSection: SettingsSection {
    let id = "test.unassigned"
    let title = "Unassigned"
    let systemImage = "questionmark"
    let sortKey = SettingsSortKey.advanced + 5
    var body: some View { Section("Unassigned") { Text("row") } }
}

@Test @MainActor func everyRegisteredSectionLandsInExactlyOneGroup() {
    for section in SettingsRegistry.sections {
        let groups = SettingsGroupId.allCases.filter { g in
            GroupSettingsView.sections(in: g).contains { $0.id == section.id }
        }
        #expect(groups.count == 1, "\(section.id) must appear in exactly one group, got \(groups.map(\.rawValue))")
    }
    // and nothing is lost: the groups partition the registry.
    let grouped = SettingsGroupId.allCases.flatMap { GroupSettingsView.sections(in: $0).map(\.id) }
    #expect(Set(grouped) == Set(SettingsRegistry.sections.map(\.id)))
    #expect(grouped.count == SettingsRegistry.sections.count)
}

/// The assignment Toby asked for on 2026-09-22 ("everything that pertains to data sync" under
/// Sync & hub) plus the carding calls (weekly plan + appearance = Home layout).
@Test @MainActor func sectionsAreAssignedToTheContractGroups() {
    let expected: [String: SettingsGroupId] = [
        HubSection.sectionId: .sync,
        DataLinksSection.sectionId: .sync,
        DataQualitySection.sectionId: .sync,
        LocalMirrorsSection.sectionId: .sync,
        ExportSection.sectionId: .sync,
        EditTodaySection.sectionId: .home,
        WeeklyPlanSection.sectionId: .home,
        AppearanceSection.sectionId: .home,
        PreferencesLinksSection.sectionId: .kpis,
        GateConfigSection.sectionId: .kpis,
        HapticsSection.sectionId: .haptics,
        RemindersSection.sectionId: .haptics,
        HealthSection.sectionId: .health,
        VersionSection.sectionId: .about,
    ]
    let actual = Dictionary(uniqueKeysWithValues: SettingsRegistry.sections.map { ($0.id, $0.group) })
    for (id, group) in expected {
        #expect(actual[id] == group, "\(id) expected in \(group.rawValue), got \(actual[id]?.rawValue ?? "missing")")
    }
}

@Test @MainActor func everyUserFacingGroupIsReachableAndTitled() {
    let shipped: [SettingsGroupId] = [.sync, .widgets, .home, .kpis, .haptics, .health, .about]
    for group in shipped { #expect(SettingsGroupId.allCases.contains(group)) }
    #expect(SettingsGroupId.allCases.prefix(7).map(\.rawValue) == shipped.map(\.rawValue))
    #expect(SettingsGroupId.sync.title == "Sync & hub")
    #expect(SettingsGroupId.home.title == "Home & Today layout")
    #expect(SettingsGroupId.kpis.title == "KPIs & alerts")
    #expect(SettingsGroupId.haptics.title == "Haptics & notifications")
    #expect(SettingsGroupId.health.title == "Health access")
    #expect(SettingsGroupId.about.title == "About & version")
    #expect(SettingsGroupId.sync.systemImage == "arrow.triangle.2.circlepath")
    #expect(SettingsGroupId.allCases.allSatisfy { !$0.systemImage.isEmpty })
    // Every shipped group but Widgets has content; Widgets says why it is empty (rule 5).
    for group in shipped where group != .widgets {
        #expect(!GroupSettingsView.sections(in: group).isEmpty, "\(group.rawValue) has no sections")
    }
    #expect(GroupSettingsView.sections(in: .widgets).isEmpty)
    #expect(SettingsGroupId.widgets.placeholder == "Widgets arrive with B-34/B-36")
    #expect(SettingsGroupId.sync.placeholder == nil)
}

@Test @MainActor func aSectionWithoutAnExplicitGroupFallsBackToItsSortKeyBand() {
    #expect(UnassignedSection().group == .about)
    #expect(SettingsGroupId(sortKey: SettingsSortKey.connection) == .sync)
    #expect(SettingsGroupId(sortKey: SettingsSortKey.preferences) == .home)
    #expect(SettingsGroupId(sortKey: SettingsSortKey.data) == .sync)
    #expect(SettingsGroupId(sortKey: SettingsSortKey.advanced + 500) == .about)
}

/// A group screen renders its sections in `sortKey` order, exactly like the old flat screen did
/// within a band — the two-level menu reorders nothing.
@Test @MainActor func aGroupScreenRendersItsSectionsInSortKeyOrder() {
    for group in SettingsGroupId.allCases {
        let keys = GroupSettingsView.sections(in: group).map(\.sortKey)
        #expect(keys == keys.sorted())
    }
    let sync = GroupSettingsView.sections(in: .sync).map(\.id)
    #expect(sync.first == HubSection.sectionId)
}

/// The data-source switch is a developer tool. In DEBUG it is registered under its own group; in
/// a Release build neither the group nor the section is compiled in at all.
@Test @MainActor func theDeveloperGroupIsDebugOnly() {
    let ids = SettingsRegistry.sections.map(\.id)
    #if DEBUG
    #expect(SettingsGroupId.allCases.contains { $0.rawValue == "developer" })
    #expect(ids.contains(ProviderSection.sectionId))
    #expect(GroupSettingsView.sections(in: .developer).map(\.id) == [ProviderSection.sectionId])
    #expect(SettingsGroupId.developer.title == "Developer")
    #expect(SettingsGroupId.developer.systemImage == "hammer")
    #else
    #expect(SettingsGroupId.allCases.contains { $0.rawValue == "developer" } == false)
    #expect(SettingsGroupId.allCases.count == 7)
    #expect(ids.contains("l3.provider") == false)
    #endif
}

/// The sweep covers the new second level: one entry per shipped group, none for Developer.
@Test @MainActor func theGallerySweepCoversEveryShippedGroupScreen() {
    let names = Set(ScreenRegistry.entries.map(\.name))
    for name in ["Settings", "Settings sync", "Settings widgets", "Settings home",
                 "Settings KPIs", "Settings haptics", "Settings health", "Settings about"] {
        #expect(names.contains(name), "missing sweep entry \(name)")
    }
    #expect(names.contains("Settings developer") == false)
}
