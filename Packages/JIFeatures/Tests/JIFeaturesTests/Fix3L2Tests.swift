import Foundation
import SwiftUI
import Testing
@testable import JIFeatures

// W-FIX3 L2 (P-settings, P-about, P-export, P-goals, P-appearance): BUG-43, 45, 46, 49,
// BUG-33 (More subtitle, Home & widgets title, Settings row icons), C-b, C-c.

private func source(_ relative: String) throws -> String {
    // Tests/JIFeaturesTests/<file> → package root → repo root.
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

// MARK: - BUG-43: the changelog reaches the current build

@Test func bug43_theChangelogLeadsWithTheInstalledReleaseAndReachesThisWeek() {
    let latest = Changelog.swiftEntries[0]
    #expect(latest.version == "2.0.0")
    #expect(latest.date >= "2026-09-25")
    #expect(Changelog.entries.first == latest)
    // One entry per Swift milestone, newest first, every version unique.
    let dates = Changelog.swiftEntries.map(\.date)
    #expect(dates == dates.sorted(by: >))
    #expect(Changelog.swiftEntries.count >= 3)
    #expect(Set(Changelog.entries.map(\.id)).count == Changelog.entries.count)
    // The 2.0.0 install row is marked "Installed" on the board.
    #expect(versionHighlights(Changelog.entries, appVersion: "2.0.0").first?.installed == true)
}

// MARK: - BUG-46: widgets have shipped

@Test func bug46_theWidgetsFooterNoLongerSaysTheyAreComing() throws {
    let text = try #require(SettingsGroupId.widgets.placeholder)
    #expect(!text.contains("arrive"))
    #expect(!text.contains("B-34"))
    #expect(text.contains("Home Screen"))
}

// MARK: - BUG-45: Export matches board 5/04

@Test @MainActor func bug45_exportStartsWithThreeOfFourTicked() {
    let model = ExportViewModel(stores: .init())
    exportApplyBoardDefaults(model)
    let ticked = ExportRow.allCases.filter { exportRowSelected($0, isSelected: model.isSelected) }
    #expect(ticked == [.journal, .mind, .who5])
    #expect(exportTickedLine(ticked.count) == "3 of 4 ticked. Nothing leaves the phone unless you tick it.")
    // A choice the user made is never overwritten.
    let chosen = ExportViewModel(stores: .init())
    chosen.toggle(.goals)
    exportApplyBoardDefaults(chosen)
    #expect(ExportRow.allCases.filter { exportRowSelected($0, isSelected: chosen.isSelected) } == [.goals])
}

@Test func bug45_exportRowsAreTickCirclesAndCsvIsThePrimaryButton() throws {
    let body = try source("Sources/JIFeatures/Export/ExportView.swift")
    #expect(body.contains("checkmark.circle.fill"))
    #expect(!body.contains("Toggle(isOn:"))
    #expect(body.contains(".borderedProminent"))
}

// MARK: - BUG-49: the goal date is a formatted date

@Test func bug49_theTargetDateRoundTripsAndReadsAsADate() {
    let date = goalsSetupDate("2026-10-31")
    #expect(date != nil)
    #expect(goalsSetupISO(date!) == "2026-10-31")
    #expect(goalsSetupDateLabel("2026-10-31") == "31 Oct 2026")
    #expect(goalsSetupDate("") == nil)
    #expect(goalsSetupDate("31.10.2026") == nil)
    #expect(goalsSetupDateLabel("") == "No target date")
}

@Test func bug49_theDateIsPickedNotTyped() throws {
    let body = try source("Sources/JIFeatures/Goals/GoalsSetupView.swift")
    #expect(!body.contains("TextField(\"YYYY-MM-DD\""))
    #expect(body.contains("DatePicker("))
}

// MARK: - BUG-33: AX3 — icons get a column that grows with the text; long titles wrap

@Test func bug33_settingsIconColumnGrowsWithTheTextSize() {
    #expect(settingsIconColumnWidth(.large) == 28)
    #expect(settingsIconColumnWidth(.xSmall) == 28)
    #expect(settingsIconColumnWidth(.accessibility3) >= 52)
    #expect(settingsIconColumnWidth(.accessibility5) > settingsIconColumnWidth(.accessibility3))
}

@Test func bug33_longTitlesMoveIntoTheListAtAccessibilitySizes() {
    #expect(jiTitleWrapsInList(.large) == false)
    #expect(jiTitleWrapsInList(.xxxLarge) == false)
    #expect(jiTitleWrapsInList(.accessibility1))
    #expect(jiTitleWrapsInList(.accessibility3))
}

@Test func bug33_moreSubtitleWrapsAtAxSizes() throws {
    let body = try source("../../App/RootTabView.swift")
    #expect(body.contains("jiTitleWrapsInList("))
}

// MARK: - C-b: open Appearance follows Dark → System live (the window override does it)

@Test func cb_appearanceDoesNotPinItsOwnColorScheme() throws {
    let body = try source("Sources/JIFeatures/Appearance/AppearanceView.swift")
    #expect(!body.contains(".preferredColorScheme("))
}

// MARK: - C-c: the user's accent wins over a hard-coded default

@Test func cc_rootTabViewDoesNotForceTheDefaultAccent() throws {
    let body = try source("../../App/RootTabView.swift")
    #expect(!body.contains("AccentKey.default"))
}
