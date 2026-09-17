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
