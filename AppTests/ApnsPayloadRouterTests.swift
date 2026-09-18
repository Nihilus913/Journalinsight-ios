import Foundation
import Testing
import JICore
@testable import JournalInsight

/// W7-L2 (P-apns-push) exit criterion: "a tapped APNs payload with `deeplink` routes to the same
/// destination as the equivalent ntfy click (shared test cases)". The shared cases are the source
/// of truth below — each one is fed through BOTH keys and the two results must be equal, so the
/// two channels can never drift apart in routing behaviour.

/// `(url string, expected destination)`. Mirrors `NtfyDeepLinkHandlerTests`' cases and adds the
/// hub's real 05:10 string, which carries a `?date=` query `DeepLink.gate` deliberately ignores
/// (`_ji_click_url()` in `HealthTraining/scripts/morning_go.py`).
private let sharedCases: [(url: String, expected: DeepLink?)] = [
    ("ji://gate", .gate),
    ("ji://gate?date=2026-09-18", .gate),
    ("journalinsight://gate", .gate),
    ("ji://kpi-detail?metric=hrv", .kpiDetail(metric: "hrv")),
    ("ji://kpi-detail", nil),
    ("https://example.com/gate", nil),
    ("ji://unknown-host", nil),
    ("not a url \u{7}", nil),
]

@Test func apnsAndNtfyPayloadsRouteIdenticallyForEveryCase() {
    for (url, expected) in sharedCases {
        let viaApns = ApnsPayloadRouter.resolve(userInfo: [ApnsPayloadRouter.deepLinkKey: url])
        let viaNtfy = ApnsPayloadRouter.resolve(userInfo: [LocalVerdictFloor.deepLinkURLKey: url])
        #expect(viaApns == expected, "APNs payload \(url) routed to \(String(describing: viaApns))")
        #expect(viaApns == viaNtfy, "APNs and ntfy disagree on \(url)")
    }
}

@Test func theHubsOwn0510DeepLinkStringRoutesToTheGate() {
    // Byte-for-byte the string the W7 card fixes as the APNs custom data.
    let userInfo: [AnyHashable: Any] = ["deeplink": "ji://gate?date=2026-09-18"]
    #expect(ApnsPayloadRouter.deepLink(fromApnsUserInfo: userInfo) == .gate)
}

@Test func apnsRoutingUsesTheSameParserNotACopy() {
    // If `ApnsPayloadRouter` ever grew its own parser, this case (host-less `ji:gate`, which only
    // `DeepLink.parse`'s path fallback handles) is what would break first.
    #expect(ApnsPayloadRouter.deepLink(fromApnsUserInfo: ["deeplink": "ji:///gate"]) == .gate)
}

@Test func anApnsPayloadWithoutADeeplinkKeyResolvesToNil() {
    #expect(ApnsPayloadRouter.deepLink(fromApnsUserInfo: [:]) == nil)
    #expect(ApnsPayloadRouter.deepLink(fromApnsUserInfo: ["aps": ["alert": "GO"]]) == nil)
}

@Test func anApnsPayloadWithANonStringDeeplinkResolvesToNil() {
    #expect(ApnsPayloadRouter.deepLink(fromApnsUserInfo: ["deeplink": 42]) == nil)
    #expect(ApnsPayloadRouter.deepLink(fromApnsUserInfo: ["deeplink": ["ji://gate"]]) == nil)
}

@Test func theLocalVerdictFloorPayloadStillRoutesThroughTheSharedResolver() {
    // Regression guard on the one-line switch in `NotificationRoutingDelegate`: the local 05:10
    // reminder has no `deeplink` key, so it must fall through to the unchanged ntfy lookup.
    let userInfo: [AnyHashable: Any] = [LocalVerdictFloor.deepLinkURLKey: LocalVerdictFloor.deepLinkURLString]
    #expect(ApnsPayloadRouter.deepLink(fromApnsUserInfo: userInfo) == nil)
    #expect(ApnsPayloadRouter.resolve(userInfo: userInfo) == .gate)
    #expect(ApnsPayloadRouter.resolve(userInfo: userInfo) == NtfyDeepLink.deepLink(fromUserInfo: userInfo))
}

@Test func anApnsDeeplinkWinsOverAStaleNtfyKeyInTheSamePayload() {
    // Both keys present is not a shape either sender produces, but the resolver's order must be
    // deterministic rather than dictionary-dependent.
    let userInfo: [AnyHashable: Any] = [
        "deeplink": "ji://kpi-detail?metric=hrv",
        "url": "ji://gate",
    ]
    #expect(ApnsPayloadRouter.resolve(userInfo: userInfo) == .kpiDetail(metric: "hrv"))
}
