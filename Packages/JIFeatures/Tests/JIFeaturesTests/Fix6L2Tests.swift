import Foundation
import SwiftUI
import Testing
import UserNotifications
import JICore
import JIPersistence
@testable import JIFeatures

// W-FIX6 L2: F6-5, F6-12, F6-13, F6-14, F6-15, F6-16 (docs/audits/2026-09-25-regression-bugs.md).

private func fix6Source(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

// MARK: - F6-12: Goals / My KPIs never say "Connect to your hub" while a hub is connected

@Test func f612HubOnlyRowSaysWhyWhenTheHubIsConnected() {
    // No hub saved → the old instruction stays true.
    #expect(settingsHubOnlySubtitle(action: "edit goals", hubConfigured: false, dataSource: .hub)
            == "Connect to your hub to edit goals")
    // Hub saved, debug data source = Apple Watch → the row names the real reason.
    let t2 = settingsHubOnlySubtitle(action: "choose KPIs", hubConfigured: true, dataSource: .appleWatch)
    #expect(!t2.contains("Connect to your hub"))
    #expect(t2.contains("Apple Watch"))
    // Hub saved and selected but the screen could not be built → never "Connect to your hub".
    #expect(!settingsHubOnlySubtitle(action: "edit goals", hubConfigured: true, dataSource: .hub).contains("Connect"))
}

/// W-TGT L3: Goals is Targets now — the phone's own document, never hub-only (no "Connect"
/// subtitle at all); the square picker (Home & widgets › On Today) keeps the truthful subtitle.
@Test func f612UnavailableRowsUseTheTruthfulSubtitle() throws {
    let settings = try fix6Source("Sources/JIFeatures/Settings/SettingsView.swift")
    #expect(!settings.contains("subtitle: \"Connect to your hub to edit goals\""))
    #expect(!settings.contains("settingsHubOnlySubtitle(action: \"edit goals\""))
    let onToday = try fix6Source("Sources/JIFeatures/HomeWidgets/OnTodaySection.swift")
    #expect(!onToday.contains("subtitle: \"Connect to your hub to choose KPIs\""))
    #expect(onToday.contains("settingsHubOnlySubtitle(action: \"choose KPIs\""))
}

// MARK: - F6-13: Hub row = host only; the last-sync time lives once, under Sync now, inset

@Test func f613HubSubtitleIsTheHostAndTheSyncCaptionSaysLastSync() {
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
    let now = ISO8601DateFormatter().date(from: "2026-09-28T05:29:00Z")!
    let last = ISO8601DateFormatter().date(from: "2026-09-28T05:10:00Z")!
    #expect(settingsHubSubtitle(host: "192.168.1.170", lastSync: last, now: now, calendar: utc) == "192.168.1.170")
    #expect(settingsSyncTrailing(syncing: false, failed: false, lastSync: last, now: now, calendar: utc) == "Last sync 05:10")
    #expect(settingsSyncTrailing(syncing: false, failed: false, lastSync: nil, now: now, calendar: utc) == "Last sync —")
    #expect(settingsSyncTrailing(syncing: true, failed: false, lastSync: last, now: now, calendar: utc) == "Syncing…")
    #expect(settingsSyncTrailing(syncing: false, failed: true, lastSync: last, now: now, calendar: utc) == "Sync failed")
    // The caption sits on the row-text inset, never on the card's 4 pt edge (clipped "05:10").
    #expect(SettingsSyncCaption.leadingInset >= 16)
}

// MARK: - F6-16: the Reminders count = what the Reminders screen shows (the pending requests)

@Test @MainActor func f616RemindersCountReadsThePendingRequests() async throws {
    let center = FakeNotificationCenter()
    let scheduler = ReminderScheduler(center: center)
    #expect(await scheduler.activeCount() == 0)
    try await scheduler.schedule(.gateFloor, at: ReminderTime(hour: 5, minute: 10), today: "2026-09-28")
    try await scheduler.scheduleHrCapCheck(confirmedOn: "2026-09-28", capBpm: 175, today: "2026-09-28")
    // Prefs never saw the gate floor (the device case): the centre is the truth.
    #expect(await scheduler.activeCount() == 2)
    try await scheduler.scheduleWorkout(.monday, at: ReminderTime(hour: 7, minute: 0))
    #expect(await scheduler.activeCount() == 3)
    #expect(settingsRemindersTrailing(count: 2) == "2 on")
    #expect(settingsRemindersTrailing(count: 0) == "Off")
}

// MARK: - F6-14 / F6-15: pushed headers and the Settings bar

@Test func f614RemindersHeaderNeverRunsUnderTheBackButton() throws {
    let body = try fix6Source("Sources/JIFeatures/Reminders/RemindersView.swift")
    // The subtitle is a line in the list, not a centred nav subtitle next to the glass back button.
    #expect(!body.contains(".navigationSubtitle("))
    #expect(body.contains("RemindersCopy.header"))
    #expect(body.contains("jiSoftTopEdge()"))
}

@Test func f615SettingsDoneIsAToolbarButtonAndTheTopEdgeIsSoft() throws {
    let body = try fix6Source("Sources/JIFeatures/Settings/SettingsView.swift")
    #expect(!body.contains("JIGlassButton(\"checkmark\", label: \"Done\")"))
    #expect(body.contains("JIToolbarButton(\"checkmark\", label: \"Done\")"))
    #expect(body.components(separatedBy: "jiSoftTopEdge()").count - 1 >= 2)   // root + pushed screens
}

// MARK: - F6-5: no green text links — "How JI …" is a chevron row

@Test func f65HowJiLinksAreChevronRows() throws {
    for file in ["Sources/JIFeatures/GateRationale/GateRationaleView.swift", "Sources/JIFeatures/Onboarding/OnboardingSteps.swift"] {
        let body = try fix6Source(file)
        #expect(!body.contains("HowWeCalculateLink("), "\(file) still draws a text link")
        #expect(body.contains("JIHowWeCalculateRow("), "\(file) draws the chevron row")
    }
}
