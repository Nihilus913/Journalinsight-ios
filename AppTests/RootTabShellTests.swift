import Testing
import SwiftUI
import UIKit
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

// MARK: - W-FIX2 BUG-14: the search-role Tab stays interactive after a pass-through tab mounted

@MainActor @Test func fix2SearchTabContentReceivesTouchesAfterAPassThroughTabMounted() {
    let passThrough = UIHostingController(rootView: Color.clear.background(TabHostPassThrough()).allowsHitTesting(false))
    let journal = UIViewController()
    let button = UIButton(type: .system)
    button.frame = CGRect(x: 100, y: 300, width: 120, height: 60)
    journal.view.addSubview(button)
    let tabs = UITabBarController()
    tabs.viewControllers = [passThrough, journal]
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    let host = UIViewController()                  // stands in for SwiftUI's platform host
    window.rootViewController = host
    host.addChild(tabs)
    tabs.view.frame = host.view.bounds
    host.view.addSubview(tabs.view)
    tabs.didMove(toParent: host)
    window.makeKeyAndVisible()
    tabs.selectedIndex = 0                     // Today mounts first (the pass-through marker runs)
    window.layoutIfNeeded()
    tabs.selectedIndex = 1                     // then the user taps Search (the Journal)
    window.layoutIfNeeded()
    let point = button.convert(CGPoint(x: 60, y: 30), to: window)
    #expect(window.hitTest(point, with: nil) === button)
    // Back on the pass-through tab, a tap above the bar still falls through (nothing claims it).
    tabs.selectedIndex = 0
    window.layoutIfNeeded()
    let hit = window.hitTest(CGPoint(x: 200, y: 400), with: nil)
    #expect(hit == nil || hit === window || hit === host.view)
    window.isHidden = true
}

// MARK: - W-B57-W2 fixer2 C3-KPI-GOALS: the user's goals reach the modal sheets too

/// A `.sheet` sees the environment where the sheet modifier sits, not modifiers applied inside it.
/// The nutritionGoals injection sat BEFORE the My KPIs / Settings sheets, so their KpiList tiles
/// and KPI detail read `.unknown` and said "Set your goal" with goals saved. It must be the
/// outermost environment write of the shell — after every `.sheet(` in `body`.
@Test func fixer2NutritionGoalsInjectionWrapsEverySheet() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "App/RootTabView.swift"), encoding: .utf8)
    let bodyStart = try #require(source.range(of: "var body: some View {"))
    let body = source[bodyStart.upperBound...]
    let injection = try #require(body.range(of: ".environment(\\.nutritionGoals"))
    var lastSheet = body.startIndex
    var cursor = body.startIndex
    // `body` ends at the first helper declared after it.
    let bodyEnd = body.range(of: "\n    /// ")?.lowerBound ?? body.endIndex
    while let r = body.range(of: ".sheet(", range: cursor..<bodyEnd) { lastSheet = r.lowerBound; cursor = r.upperBound }
    #expect(lastSheet > body.startIndex, "body presents sheets")
    #expect(injection.lowerBound > lastSheet, "nutritionGoals must be injected after the last .sheet")
}

// MARK: - W-B57-W4 LC guard, BUG-21: the My KPIs sheet keeps its Done button and its own stack

/// BUG-21 (W-FIX2): the My KPIs sheet had no Done (swipe-down was the only way out) and its squares
/// did nothing. The sheet must carry a confirmation-placement Done that closes it, and a square tap
/// must push KPI detail inside the sheet's own path.
@Test func bug21MyKpisSheetHasDoneAndPushesSquaresInItsOwnStack() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "App/RootTabView.swift"), encoding: .utf8)
    let sheet = try #require(source.range(of: ".sheet(isPresented: $showKpiList"))
    let block = source[sheet.upperBound...].prefix(2500)
    #expect(block.contains("NavigationStack(path: $kpiSheetPath)"))
    #expect(block.contains("ToolbarItem(placement: .confirmationAction)"))
    #expect(block.contains("label: \"Done\") { showKpiList = false }"))
    #expect(block.contains(".accessibilityIdentifier(\"kpis.done\")"))
    #expect(block.contains("kpiSheetPath.append(route)"))
}

// MARK: - W-B57-W4 C5: first-launch onboarding order (Review Focus 4)

@Test func onboardingPresentationRules() {
    #expect(RootTabView.firstSheet(needsOnboarding: true, needsConnection: true, arguments: []) == .onboarding)
    #expect(RootTabView.firstSheet(needsOnboarding: false, needsConnection: true, arguments: []) == .connection)
    #expect(RootTabView.firstSheet(needsOnboarding: false, needsConnection: false, arguments: []) == nil)
    #expect(RootTabView.firstSheet(needsOnboarding: true, needsConnection: true, arguments: ["-no-onboarding"]) == .connection)
    #expect(RootTabView.firstSheet(needsOnboarding: true, needsConnection: false, arguments: ["-no-onboarding"]) == nil)
}

/// The pre-W4 migration runs BEFORE onboarding reads the store, and the gate settings reach every
/// sheet (outermost injection, like nutritionGoals).
@Test func gateSettingsMigrateFirstAndWrapEverySheet() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "App/RootTabView.swift"), encoding: .utf8)
    let migrate = try #require(source.range(of: "migratePreW4InstallIfNeeded()"))
    let firstSheet = try #require(source.range(of: "Self.firstSheet(needsOnboarding:"))
    #expect(migrate.lowerBound < firstSheet.lowerBound)
    let bodyStart = try #require(source.range(of: "var body: some View {"))
    let body = source[bodyStart.upperBound...]
    let bodyEnd = body.range(of: "\n    /// ")?.lowerBound ?? body.endIndex
    let injection = try #require(body.range(of: ".environment(\\.gateSettings", range: body.startIndex..<bodyEnd))
    var lastSheet = body.startIndex
    var cursor = body.startIndex
    while let r = body.range(of: ".sheet(", range: cursor..<bodyEnd) { lastSheet = r.lowerBound; cursor = r.upperBound }
    #expect(injection.lowerBound > lastSheet)
}

@Test func daytimeHrvIsNilWithoutATodayModel() {
    #expect(RootTabView.daytimeHrv(nil) == nil)
}
