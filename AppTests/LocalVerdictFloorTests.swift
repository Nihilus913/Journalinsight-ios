import Testing
import Foundation
import UserNotifications
@testable import JournalInsight

// W2c-L4 exit criterion: "notification request built for 05:10 (unit test)". Exercises the pure
// builders in LocalVerdictFloor — no UNUserNotificationCenter round trip needed.

@Test func verdictFloorRequestDefaultsTo0510() {
    let request = LocalVerdictFloor.request()
    guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
        Issue.record("expected a calendar trigger")
        return
    }
    #expect(trigger.dateComponents.hour == 5)
    #expect(trigger.dateComponents.minute == 10)
    #expect(trigger.repeats == true)
}

@Test func verdictFloorRequestHonorsCustomTime() {
    let request = LocalVerdictFloor.request(hour: 6, minute: 30)
    let trigger = request.trigger as? UNCalendarNotificationTrigger
    #expect(trigger?.dateComponents.hour == 6)
    #expect(trigger?.dateComponents.minute == 30)
}

@Test func verdictFloorRequestUsesStableIdentifier() {
    #expect(LocalVerdictFloor.request().identifier == LocalVerdictFloor.identifier)
}

@Test func verdictFloorContentCarriesGateDeepLink() {
    let content = LocalVerdictFloor.content()
    #expect(content.userInfo[LocalVerdictFloor.deepLinkURLKey] as? String == "ji://gate")
    #expect(content.title == LocalVerdictFloor.title)
    #expect(!content.body.isEmpty)
}
