import Testing
@testable import JournalInsight

// W3a L4 (tab shell): pure shape checks for `RootTab`. The tabs' cast-fallback behavior
// (`env.providerStore?.provider as? any EnergyProviding` etc. → `ContentUnavailableView`, never a
// blank tab) lives in `RootTabView`'s view body and needs the L1–L3 sibling lanes' types
// (`EnergyProviding`/`EnergyViewModel`/`EnergyView` and their Nutrition/Training equivalents) to
// even compile — those land in the same wave's parallel lanes and aren't present in this lane's
// worktree, so that behavior is exercised at the wave's integration/sim-smoke step, not here
// (wave card Orchestrator: "sim smoke of the three tabs"). This file only pins the tab
// vocabulary L4 owns.

@Test func rootTabHasOneCaseForEachW3aTabScreen() {
    let tabs: Set<RootTab> = [.today, .recovery, .energy, .nutrition, .training]
    #expect(tabs.count == 5)
}

// B-46 device feedback 1 (Toby 2026-09-22): iOS 27 counts the search role against the bar's five
// slots, so five content tabs + search folded two of them into a system "More". The bar is four
// explicit icons — Today · Recovery · Training · More — plus the search Tab hosting the Journal.
@Test func firstLevelTabsAreFourIconsEndingInOurOwnMore() {
    #expect(RootTab.firstLevel == [.today, .recovery, .training, .more])
    #expect(!RootTab.firstLevel.contains(.search))
    #expect(!RootTab.firstLevel.contains(.nutrition))
    #expect(!RootTab.firstLevel.contains(.energy))
    #expect(RootTab.firstLevel.map(\.accessibilityIdentifier).first == "tab.today")
    #expect(RootTab.more.accessibilityIdentifier == "tab.more")
}

// Nutrition and Energy keep their cases: `moreTab` links straight to the same screens.
@Test func moreTabHostsNutritionAndEnergy() {
    #expect(RootTab.more.title == "More")
    #expect(RootTab.nutrition.title == "Nutrition")
    #expect(RootTab.energy.title == "Energy")
}

// B-46 device feedback 10: no deep link and no toolbar button may map to `.kpiList` as a ROOT
// path push any more — the crash was `path.append(.kpiList)` from a tab with its own stack.
@Test func noDeepLinkPushesTheKpiList() {
    #expect(RootRoute.destination(for: .gate) == nil)
    #expect(RootRoute.destination(for: .kpiDetail(metric: "hrv")) == .kpiDetail(metric: "hrv"))
}

@Test func launchArgumentsSelectATabAndTheKpiList() {
    #expect(RootTabView.launchArgumentTab(["x", "-start-tab", "training"]) == .training)
    #expect(RootTabView.launchArgumentTab(["x", "-start-tab", "nope"]) == nil)
    #expect(RootTabView.launchArgumentTab(["x"]) == nil)
    #expect(RootTabView.launchArgumentRoute(["x", "-push-route", "kpiList"]) == .kpiList)
    #expect(RootTabView.launchArgumentRoute(["x"]) == nil)
}
