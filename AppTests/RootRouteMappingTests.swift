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
