import Foundation
import Testing
import UserNotifications
@testable import JournalInsight

// RG-60 (B-21): `xcrun simctl push` fails on the Simulator with UNErrorDomain 2003 ("Source is not
// authorized"), so a hub push cannot be delivered end-to-end there. These tests drive a MOCK APNs
// payload through the app's own seams instead: foreground presentation + tap routing.
@Suite struct MockPushPresentationTests {
    /// The Morning GO alert push as the hub's ApnsSink builds it (aps alert + custom `deeplink`).
    static let morningGoPush: [AnyHashable: Any] = [
        "aps": ["alert": ["title": "Your call: Full", "body": "Norwegian 4x4"], "sound": "default"],
        "deeplink": "ji://gate?date=2026-10-06",
    ]

    @Test func aForegroundPushIsShownAsABannerNotSwallowed() {
        let p = NotificationRoutingDelegate.foregroundPresentation
        #expect(p.contains(.banner) && p.contains(.sound) && p.contains(.list))
    }

    @Test func aTappedMockPushRoutesToDecide() {
        #expect(ApnsPayloadRouter.resolve(userInfo: Self.morningGoPush) == .gate)
    }

    @Test func aMockPushWithoutADeeplinkRoutesNowhere() {
        #expect(ApnsPayloadRouter.resolve(userInfo: ["aps": ["alert": "x"]]) == nil)
    }
}
