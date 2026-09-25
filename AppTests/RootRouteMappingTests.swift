import Testing
import Foundation
@testable import JournalInsight

// Pure mapping seam (RootRoute.destination) between a parsed DeepLink and what RootTabView
// pushes onto its NavigationPath — exercised directly rather than through a live UI tap, per
// W2b-L3's acceptance criteria.

@Test func kpiDetailDeepLinkMapsToKpiDetailRoute() {
    let link = DeepLink.parse(URL(string: "ji://kpi-detail?metric=hrv")!)
    #expect(link == .kpiDetail(metric: "hrv"))
    #expect(RootRoute.destination(for: link!) == .kpiDetail(metric: "hrv"))
}

@Test func gateDeepLinkHasNoPushDestination() {
    #expect(RootRoute.destination(for: .gate) == nil)
}

@Test func chipTapSelectionMapsToTheSameRouteAsADeepLink() {
    // TodayView's onSelectKpi hands RootTabView a bare chip id (e.g. "rhr") — confirm it
    // resolves to the identical route a deep link for that metric would produce.
    let fromChipTap = RootRoute.kpiDetail(metric: "rhr")
    let fromDeepLink = RootRoute.destination(for: .kpiDetail(metric: "rhr"))
    #expect(fromDeepLink == fromChipTap)
}

// MARK: - B-55 per-tab routing seam (the rapid-tap crash)

@Test func b55PushLandsOnTheOwningTabsStackOnly() {
    var router = TabRouter()
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    let pushed1 = router.push(.kpiDetail(metric: "hrv"), now: t0)
    #expect(pushed1)
    #expect(router.path(for: .today) == [.kpiDetail(metric: "hrv")])
    for tab in RootTab.allCases where tab != .today { #expect(router.path(for: tab).isEmpty) }
}

@Test func b55KpiRoutesAndDeepLinksAreOwnedByToday() {
    #expect(TabRouter.owner(of: .kpiDetail(metric: "rhr")) == .today)
    #expect(TabRouter.owner(of: .kpiList) == .today)
    let route = RootRoute.destination(for: .kpiDetail(metric: "rhr"))!
    #expect(TabRouter.owner(of: route) == .today)
}

@Test func b55RapidSecondPushInsideOnePushAnimationIsDropped() {
    var router = TabRouter()
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    let pushed2 = router.push(.kpiDetail(metric: "hrv"), now: t0)
    #expect(pushed2)
    // Two different tiles tapped back-to-back: the second must not append inside the same update.
    let pushed3 = router.push(.kpiDetail(metric: "rhr"), now: t0)
    #expect(!pushed3)
    let pushed4 = router.push(.kpiDetail(metric: "rhr"), now: t0.addingTimeInterval(TabRouter.reentryInterval / 2))
    #expect(!pushed4)
    #expect(router.path(for: .today) == [.kpiDetail(metric: "hrv")])
    let pushed5 = router.push(.kpiDetail(metric: "rhr"), now: t0.addingTimeInterval(TabRouter.reentryInterval + 0.01))
    #expect(pushed5)
    #expect(router.path(for: .today) == [.kpiDetail(metric: "hrv"), .kpiDetail(metric: "rhr")])
}

@Test func b55DoubleTapOnTheSameTileNeverStacksTheRouteTwice() {
    var router = TabRouter()
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    let pushed6 = router.push(.kpiDetail(metric: "hrv"), now: t0)
    #expect(pushed6)
    let pushed7 = router.push(.kpiDetail(metric: "hrv"), now: t0.addingTimeInterval(5))
    #expect(!pushed7)
    #expect(router.path(for: .today).count == 1)
}

@Test func b55StackPopIsWrittenBackAndPushWorksAgainAfterward() {
    var router = TabRouter()
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    router.push(.kpiDetail(metric: "hrv"), now: t0)
    router.setPath([], for: .today)                       // system back button
    #expect(router.path(for: .today).isEmpty)
    let pushed8 = router.push(.kpiDetail(metric: "hrv"), now: t0.addingTimeInterval(1))
    #expect(pushed8)
    #expect(router.path(for: .today) == [.kpiDetail(metric: "hrv")])
}

@Test func b55ABackwardsClockNeverLocksPushesOut() {
    var router = TabRouter()
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    router.push(.kpiDetail(metric: "hrv"), now: t0)
    let pushed9 = router.push(.kpiDetail(metric: "rhr"), now: t0.addingTimeInterval(-60))
    #expect(pushed9)
}

// MARK: - W-FIX2 BUG-13: a KPI detail pushes on the tab it came from

@Test func fix2KpiDetailPushesOnTheOriginatingTab() {
    var router = TabRouter()
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    // A Recovery tile tap: the detail lands on Recovery's stack, Today's stays untouched.
    let p1 = router.push(.kpiDetail(metric: "hrv"), on: .recovery, now: t0)
    #expect(p1)
    #expect(router.path(for: .recovery) == [.kpiDetail(metric: "hrv")])
    #expect(router.path(for: .today).isEmpty)
    // Back (the stack's own write) returns to Recovery's root.
    router.setPath([], for: .recovery)
    #expect(router.path(for: .recovery).isEmpty)
}

@Test func fix2ReentryGuardIsPerTab() {
    var router = TabRouter()
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    let p2 = router.push(.kpiDetail(metric: "hrv"), on: .recovery, now: t0)
    #expect(p2)
    // A different tab's stack is not blocked by Recovery's in-flight push.
    let p3 = router.push(.kpiDetail(metric: "rhr"), on: .more, now: t0)
    #expect(p3)
    #expect(router.path(for: .more) == [.kpiDetail(metric: "rhr")])
}

// MARK: - W-FIX2 DEV-04: ji://gate focuses Today at its root and opens Decide

@Test func fix2GateDeepLinkParsesAndPopsTodayToRoot() {
    #expect(DeepLink.parse(URL(string: "ji://gate")!) == .gate)
    var router = TabRouter()
    router.push(.kpiDetail(metric: "hrv"), on: .today, now: Date(timeIntervalSinceReferenceDate: 1_000))
    router.popToRoot(.today)
    #expect(router.path(for: .today).isEmpty)
}
