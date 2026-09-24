import Foundation
import Testing
import JICore
import JIHub
import JIHealthKit
import JIPersistence
@testable import JIFeatures

// B-57 W1 fixer g3 (r4) — the Settings family laid out from the v11 boards: Settings root
// (Sync now, badges, trailing values), Data quality (three compact source rows), Local mirrors,
// Appearance, Version and Health permission. Every value comes from existing state; a missing
// input is "—" (plus a reason word where a row has room), never a zero.

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func at(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

// MARK: - Settings root trailing values

@Test func goalsTrailingShowsBaseToTargetOrJustTheTarget() {
    let nutrition = NutritionGoal(kcalGoal: 2000, proteinG: 150, carbsG: 200, fatG: 60)
    let full = Goals(weight: WeightGoal(baseKg: 80.2, targetKg: 75), strength: [], nutrition: nutrition)
    #expect(settingsGoalsTrailing(full) == "80.2 → 75.0 kg")
    let noBase = Goals(weight: WeightGoal(targetKg: 75), strength: [], nutrition: nutrition)
    #expect(settingsGoalsTrailing(noBase) == "Target 75.0 kg")
    #expect(settingsGoalsTrailing(nil) == nil)
}

@Test func remindersTrailingCountsEveryEnabledReminder() {
    var prefs = RemindersPrefs()
    #expect(settingsRemindersTrailing(nil) == "Off")
    #expect(settingsRemindersTrailing(prefs) == "Off")
    prefs.daily["journal"] = .init(enabled: true, time: ReminderTime(hour: 21, minute: 0))
    prefs.daily["checkin"] = .init(enabled: false, time: ReminderTime(hour: 9, minute: 0))
    prefs.workouts["2"] = .init(enabled: true, time: ReminderTime(hour: 7, minute: 0))
    #expect(settingsRemindersTrailing(prefs) == "2 on")
}

@Test func kpisTrailingSaysChosen() {
    #expect(settingsKpisTrailing(4) == "4 chosen")
    #expect(settingsKpisTrailing(0) == "None chosen")
}

@Test func syncTrailingPrefersTheStateOverTheTime() {
    let now = at("2026-09-24T12:00:00Z")
    #expect(settingsSyncTrailing(syncing: true, failed: false, lastSync: nil, now: now, calendar: utc) == "Syncing…")
    #expect(settingsSyncTrailing(syncing: false, failed: true, lastSync: now, now: now, calendar: utc) == "Failed")
    #expect(settingsSyncTrailing(syncing: false, failed: false, lastSync: at("2026-09-24T07:41:00Z"), now: now, calendar: utc) == "07:41")
    #expect(settingsSyncTrailing(syncing: false, failed: false, lastSync: at("2026-09-20T07:41:00Z"), now: now, calendar: utc) == "20 Sep")
    #expect(settingsSyncTrailing(syncing: false, failed: false, lastSync: nil, now: now, calendar: utc) == "—")
}

@Test func hubRowSaysHostAndLastSyncAndABadgeOnlyFromATest() {
    let now = at("2026-09-24T12:00:00Z")
    #expect(settingsHubSubtitle(host: nil, lastSync: nil, now: now, calendar: utc) == "Not set up")
    #expect(settingsHubSubtitle(host: "192.168.1.5", lastSync: nil, now: now, calendar: utc) == "192.168.1.5")
    #expect(settingsHubSubtitle(host: "192.168.1.5", lastSync: at("2026-09-24T07:41:00Z"), now: now, calendar: utc)
            == "192.168.1.5 · last sync 07:41")
    #expect(settingsHubBadge(nil, testing: false) == nil)
    #expect(settingsHubBadge(nil, testing: true)?.word == "Checking…")
    #expect(settingsHubBadge(.ok(lastSync: nil), testing: false) == BoardStatus(word: "Connected", systemImage: "checkmark", role: .go))
    #expect(settingsHubBadge(.unauthorized, testing: false)?.role == .danger)
    #expect(settingsHubBadge(.unreachable("x"), testing: false)?.word == "Not connected")
}

@Test func healthBadgeFollowsThePermission() {
    #expect(settingsHealthBadge(.granted)?.word == "Connected")
    #expect(settingsHealthBadge(.denied)?.word == "Declined")
    #expect(settingsHealthBadge(.notDetermined)?.word == "Not connected")
    #expect(settingsHealthBadge(nil) == nil)
}

@Test func dataQualityRowBadgeCountsStaleSources() {
    #expect(settingsDataQualityBadge(stale: nil) == nil)
    #expect(settingsDataQualityBadge(stale: 0) == BoardStatus(word: "All fresh", systemImage: "checkmark", role: .go))
    #expect(settingsDataQualityBadge(stale: 2) == BoardStatus(word: "2 stale", systemImage: "exclamationmark.triangle", role: .danger))
}

// MARK: - Settings root structure

@Test func rootHasSyncNowUnderConnectionAndHapticsAsAToggle() {
    let connection = SettingsRoot.rows.filter { $0.group == .connection }.map(\.id)
    #expect(connection == ["hub", "health", "syncNow"])
    let prefs = SettingsRoot.rows.filter { $0.group == .preferences }
    #expect(prefs.map(\.id) == ["preferences", "home", "haptics"])
    #expect(prefs.first { $0.id == "haptics" }?.kind == .hapticsToggle)
    #expect(prefs.first { $0.id == "preferences" }?.sectionIds == ["l0.preferences", "l1.appearance", "l2.reminders"])
}

@Test @MainActor func gateConfigAndHapticStrengthMoveUnderAdvanced() {
    let advanced = SettingsRoot.rows.filter { $0.group == .advanced }
    let ids = advanced.flatMap(\.sectionIds)
    #expect(ids.contains(GateConfigSection.sectionId))
    #expect(ids.contains(HapticsSection.sectionId))
    #expect(ids.first == VersionSection.sectionId)
    #expect(SettingsRoot.rows.filter { $0.group == .preferences }.flatMap(\.sectionIds).contains(GateConfigSection.sectionId) == false)
}

@MainActor
private func settingsModel(sync: (@MainActor () async throws -> Void)?, now: Date = at("2026-09-24T07:41:00Z")) throws -> SettingsViewModel {
    SettingsViewModel(store: ConnectionConfigStore(secrets: InMemorySecretStore()), prefs: PrefStore(db: try AppDatabase.inMemory()),
                      syncAction: sync, now: { now }, onSaved: { _ in })
}

@Test @MainActor func syncNowRunsTheInjectedActionAndRecordsWhenItStarted() async throws {
    var calls = 0
    let model = try settingsModel(sync: { calls += 1 })
    #expect(model.canSyncNow)
    #expect(model.lastSyncDate == nil)
    await model.syncNow()
    #expect(calls == 1)
    #expect(model.syncing == false)
    #expect(model.syncFailed == false)
    #expect(model.lastSyncDate == at("2026-09-24T07:41:00Z"))
}

@Test @MainActor func syncNowFailureIsSaidNotSwallowed() async throws {
    struct Boom: Error {}
    let model = try settingsModel(sync: { throw Boom() })
    await model.syncNow()
    #expect(model.syncFailed)
    #expect(model.lastSyncDate == nil)
}

@Test @MainActor func withoutASyncActionTheRowIsNotOffered() throws {
    let model = try settingsModel(sync: nil)
    #expect(model.canSyncNow == false)
}

// MARK: - Data quality: three compact source rows

private func q(_ source: String, _ dso: Int, _ metric: String, _ composite: Double) -> QualityScoreEntry {
    QualityScoreEntry(source: source, dsoKey: dso, metric: metric, metricLabel: metric, composite: composite,
                      subScores: QualitySubScores(freshness: nil, rangeValidity: nil, trust: nil),
                      weightsUsed: [:], componentsAvailable: [], componentsMissing: [])
}

@Test func dataQualityFamiliesGroupSourcesIntoTheBoardsThreeRows() {
    let report = DataQualityReport(
        generatedAt: "2026-09-24T07:41:00Z",
        qualityScore: [q("AppleHealth", 4, "hrv", 0.9), q("AppleHealth", 4, "sleep", 0.7),
                       q("GarminAPI", 2, "steps", 0.8), q("GarminDB", 1, "activity", 0.4)],
        freshness: [],
        sourceTrust: [SourceTrustEntry(dsoKey: 2, sourceLabel: "GarminAPI", metricClass: "hr", trustTier: "trusted", note: "n")],
        provenanceGap: "Provenance is not scored yet."
    )
    let rows = dataQualityFamilies(report)
    #expect(rows.map(\.family) == [.appleWatch, .garmin, .yazio])
    #expect(rows.map(\.family.title) == ["Apple Watch", "Garmin", "YAZIO"])
    #expect(rows[0].percent == 80)
    #expect(rows[0].scores.count == 2)
    #expect(rows[1].percent == 60)
    #expect(rows[1].trust.count == 1)
    // No YAZIO rows: the row stays, its value is "—" with a reason, never 0 %.
    #expect(rows[2].percent == nil)
    #expect(rows[2].trailing == "— No data")
    #expect(rows[0].trailing == "80%")
}

@Test func dataQualityFamilyReadsTheDsoKeyFirstAndKeepsUnknownSourcesVisible() {
    #expect(DataQualityFamily(dsoKey: 1, source: "x") == .garmin)
    #expect(DataQualityFamily(dsoKey: 3, source: "x") == .yazio)
    #expect(DataQualityFamily(dsoKey: 4, source: "x") == .appleWatch)
    #expect(DataQualityFamily(dsoKey: 5, source: "Manual") == .other)
    let report = DataQualityReport(generatedAt: "", qualityScore: [q("Manual", 5, "weight", 1)], freshness: [],
                                   sourceTrust: [], provenanceGap: "")
    #expect(dataQualityFamilies(report).map(\.family) == [.appleWatch, .garmin, .yazio, .other])
}

// MARK: - Appearance

@Test func appearanceSliderStepsSkipAutoWhichIsItsOwnSwitch() {
    #expect(appearanceTextSizeSteps == [.small, .default, .large, .xlarge])
    #expect(appearanceSliderIndex(.system) == nil)
    #expect(appearanceSliderIndex(.large) == 2)
    #expect(appearanceThemeCaption(.dark) == "Dark keeps the metric colours at full strength.")
    #expect(appearanceAccentCaption == "Links and the selected tab. Metric colours never change.")
}

// MARK: - Version

@Test func versionHighlightsAreTheLatestThreeAndMarkTheInstalledOne() {
    let rows = versionHighlights(Changelog.entries, appVersion: "2.0.0")
    #expect(rows.count == 3)
    #expect(rows.map(\.entry.version) == ["2.0.0", "1.18.2", "1.18.1"])
    #expect(rows.map(\.installed) == [true, false, false])
    #expect(versionShortDate("2026-09-17") == "17 Sep")
    #expect(versionShortDate("garbage") == "garbage")
}

// MARK: - Health permission

@Test func healthReadListNamesWhatJIReadsAndNeverClaimsWorkouts() {
    let granted = healthReadRows(permission: .granted, capabilities: [.hrvSDNN, .hrvRMSSD])
    #expect(granted.map(\.title) == ["Overnight HRV", "Sleep", "Resting HR", "Workouts"])
    #expect(granted[0].subtitle == "RMSSD, the gate signal")
    #expect(granted[0].status == BoardStatus(word: "Read", systemImage: "checkmark", role: .go))
    #expect(granted[3].status.word == "Not read yet")
    let sdnnOnly = healthReadRows(permission: .granted, capabilities: [.hrvSDNN])
    #expect(sdnnOnly[0].subtitle == "SDNN until RMSSD is in Health")
    let asked = healthReadRows(permission: .notDetermined, capabilities: [.hrvSDNN])
    #expect(asked[0].status.word == "Not asked")
    #expect(healthReadRows(permission: .denied, capabilities: [.hrvSDNN])[1].status.word == "Declined")
}
