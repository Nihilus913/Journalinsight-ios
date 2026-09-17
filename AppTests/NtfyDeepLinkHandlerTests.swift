import Testing
import Foundation
@testable import JournalInsight

// W2c-L4 exit criterion: "tap routes to the gate". `NtfyDeepLink.deepLink(fromUserInfo:)` is the
// pure seam a `UNNotificationResponse` tap (LocalVerdictFloor's own reminder, or any future
// notification carrying the same `data.url` shape) is resolved through before landing in
// `RootTabView.handle(_:)`, which focuses the Today tab for `.gate` — the same tab that renders
// `ScreenState.staleVerdictDate` when the hub was asleep past 05:10, so this routing is what makes
// that banner reachable from a tap rather than only from already having the app open.

@Test func verdictFloorPayloadRoutesToGate() {
    let userInfo: [AnyHashable: Any] = [LocalVerdictFloor.deepLinkURLKey: LocalVerdictFloor.deepLinkURLString]
    #expect(NtfyDeepLink.deepLink(fromUserInfo: userInfo) == .gate)
}

@Test func kpiDetailPayloadRoutesToKpiDetail() {
    let userInfo: [AnyHashable: Any] = ["url": "ji://kpi-detail?metric=hrv"]
    #expect(NtfyDeepLink.deepLink(fromUserInfo: userInfo) == .kpiDetail(metric: "hrv"))
}

@Test func missingUrlKeyReturnsNil() {
    #expect(NtfyDeepLink.deepLink(fromUserInfo: [:]) == nil)
}

@Test func malformedUrlStringReturnsNil() {
    let userInfo: [AnyHashable: Any] = ["url": "not a url \u{7}"]
    #expect(NtfyDeepLink.deepLink(fromUserInfo: userInfo) == nil)
}

@Test func unrecognizedSchemeReturnsNil() {
    let userInfo: [AnyHashable: Any] = ["url": "https://example.com/gate"]
    #expect(NtfyDeepLink.deepLink(fromUserInfo: userInfo) == nil)
}

@Test func nonStringUrlValueReturnsNil() {
    let userInfo: [AnyHashable: Any] = ["url": 42]
    #expect(NtfyDeepLink.deepLink(fromUserInfo: userInfo) == nil)
}
