import CryptoKit
import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

// W5a-L4 (P-version). Mirrors `mobile/__tests__/version/versionScreen.render.test.tsx` (identity +
// changelog render) and `mobile/src/data/versionSeen.ts` (what's-new "seen" marker), ported onto
// `PrefStore`. The RN changelog itself is asserted byte-exact against a node-computed digest.

@MainActor
private func makeModel(appVersion: String = "1.0", build: String = "7") throws -> (VersionViewModel, PrefStore) {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let info = VersionInfo(appName: Changelog.appName, appVersion: appVersion, build: build, bundleId: "toby913.JournalInsight")
    return (VersionViewModel(prefs: prefs, info: info), prefs)
}

// MARK: - Changelog (verbatim port of `mobile/src/version/changelog.ts`)

/// SHA-256 over every RN entry's `version`/`date`/`title`/`items` (US-joined fields, RS-joined
/// entries), computed with node over the oracle's `CHANGELOG` on 2026-09-17. Any drift in a
/// single character of the port fails here.
private let rnChangelogDigest = "322cb458e0e15992e20ec7da5f37718ecedbbf50d2cb32408373dd821c0a3775"

@Test func changelogRnEntriesAreVerbatim() {
    let rn = Changelog.rnEntries
    #expect(rn.count == 27)
    #expect(rn.reduce(0) { $0 + $1.items.count } == 162)
    #expect(rn.first?.version == Changelog.rnAppVersion)
    #expect(rn.first?.version == "1.18.2")
    #expect(rn.last?.version == "1.0.0")
    let canon = rn.map { ([$0.version, $0.date, $0.title] + $0.items).joined(separator: "\u{1f}") }
        .joined(separator: "\u{1e}")
    let digest = SHA256.hash(data: Data(canon.utf8)).map { String(format: "%02x", $0) }.joined()
    #expect(digest == rnChangelogDigest)
}

@Test func changelogLeadsWithTheSwiftNativeEntryThenEveryRnEntry() {
    let all = Changelog.entries
    // W-FIX3 BUG-43: the Swift entries (newest first) lead; the "Swift native" one is the oldest of them.
    #expect(all.first?.id == Changelog.swiftEntries.first?.id)
    #expect(Changelog.swiftEntries.last == Changelog.swiftNativeEntry)
    #expect(Changelog.swiftNativeEntry.title.contains("Swift native"))
    #expect(Array(all.dropFirst(Changelog.swiftEntries.count)) == Changelog.rnEntries)
    #expect(Set(all.map(\.id)).count == all.count, "entry ids (versions) must be unique")
    #expect(Changelog.appName == "JournalInsight")
}

// MARK: - View model

@Test @MainActor func versionViewModelExposesBundleIdentityAndEveryEntry() throws {
    let (m, _) = try makeModel(appVersion: "1.0", build: "7")
    #expect(m.appName == "JournalInsight")
    #expect(m.versionLine == "Version 1.0 (7)")
    #expect(m.bundleId == "toby913.JournalInsight")
    #expect(m.entries == Changelog.entries)
    #expect(m.entries.count == Changelog.swiftEntries.count + 27)
}

@Test @MainActor func versionViewModelSeenMarkerPersistsThroughPrefStore() throws {
    let (m, prefs) = try makeModel(appVersion: "1.0")
    #expect(try prefs.get(Changelog.seenPrefKey, as: String.self) == nil)
    #expect(VersionViewModel.hasNewVersion(prefs: prefs, appVersion: "1.0") == true)

    m.markSeen()
    #expect(try prefs.get(Changelog.seenPrefKey, as: String.self) == "1.0")
    #expect(VersionViewModel.hasNewVersion(prefs: prefs, appVersion: "1.0") == false)

    // A later build re-arms the dot (RN: `seen !== APP_VERSION`).
    #expect(VersionViewModel.hasNewVersion(prefs: prefs, appVersion: "1.1") == true)
    // A fresh model over the same store sees the marker.
    let again = VersionViewModel(prefs: prefs, info: VersionInfo(appName: "x", appVersion: "1.0", build: "1", bundleId: "b"))
    #expect(again.hasBeenSeen)
}

@Test @MainActor func versionSectionRegistersInTheAdvancedBand() {
    let ids = SettingsRegistry.sections.map(\.id)
    #expect(ids.contains(VersionSection.sectionId))
    let section = VersionSection()
    #expect(SettingsGroup(sortKey: section.sortKey) == .advanced)
    #expect(section.title == "About & version")
}

@Test func versionInfoFallsBackWhenBundleKeysAreMissing() throws {
    // An empty directory is a bundle with no Info.plist — every key is missing.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ji-empty-\(UUID().uuidString).bundle")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let info = VersionInfo(bundle: try #require(Bundle(url: dir)))
    #expect(info.appName == Changelog.appName)
    #expect(info.appVersion == "0")
    #expect(info.build == "0")
    #expect(info.bundleId == "toby913.JournalInsight")
}

@Test func settingsVersionRowShowsTheBuildNumber() {
    let info = VersionInfo(appName: "JournalInsight", appVersion: "2.0.0", build: "2609280826", bundleId: "toby913.JournalInsight")
    #expect(settingsVersionTrailing(info) == "2.0.0 (2609280826)")
    let dev = VersionInfo(appName: "JournalInsight", appVersion: "2.0.0", build: "1", bundleId: "toby913.JournalInsight")
    #expect(settingsVersionTrailing(dev) == "2.0.0")
}

// MARK: - B-18 p2: "Last crash" section

@MainActor
private func makeCrashModel(_ records: [CrashRecord]) throws -> (VersionViewModel, CrashLogStore) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VersionVMCrash-\(UUID().uuidString)", isDirectory: true)
    let store = CrashLogStore(directory: dir)
    for r in records { try store.write(r) }
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let info = VersionInfo(appName: Changelog.appName, appVersion: "2.0.0", build: "42", bundleId: "toby913.JournalInsight")
    return (VersionViewModel(prefs: prefs, info: info, crashStore: store), store)
}

private let crashT0 = Date(timeIntervalSince1970: 1_791_000_000) // 2026-10-03 04:00 UTC

@Test @MainActor func versionCrashEmptyStateHasNoLastCrash() throws {
    let (m, _) = try makeCrashModel([])
    #expect(m.lastCrash == nil)
    #expect(m.crashes.isEmpty)
    #expect(m.crashReportText.isEmpty)
    // No store at all (e.g. a preview) is also the empty state, and Clear is a no-op.
    let none = VersionViewModel(prefs: PrefStore(db: try AppDatabase.inMemory()),
                                info: VersionInfo(appName: "x", appVersion: "1", build: "1", bundleId: "b"), crashStore: nil)
    #expect(none.lastCrash == nil)
    none.clearCrashes()
    #expect(none.crashes.isEmpty && none.crashClearError == nil)
}

@Test @MainActor func versionCrashPopulatedShowsNewestFirstWithReport() throws {
    let older = CrashRecord(id: "a", date: crashT0, source: .metricKit, appVersion: "2.0.0", build: "41", type: "SIGSEGV", summary: "EXC_BAD_ACCESS (code 1)")
    let newer = CrashRecord(id: "b", date: crashT0.addingTimeInterval(60), source: .exception, appVersion: "2.0.0", build: "42",
                            type: "NSInvalidArgumentException", summary: "unrecognized selector", callStack: ["0 CoreFoundation", "1 libobjc"])
    let (m, _) = try makeCrashModel([older, newer])
    #expect(m.crashes.map(\.id) == ["b", "a"])
    #expect(m.lastCrash?.type == "NSInvalidArgumentException")
    #expect(VersionViewModel.crashBuildLine(newer) == "2.0.0 · build 42")
    #expect(VersionViewModel.crashSourceLine(newer) == "Uncaught exception")
    #expect(VersionViewModel.crashSourceLine(older) == "MetricKit")
    #expect(VersionViewModel.crashDateLine(crashT0, timeZone: TimeZone(identifier: "UTC")!) == "3 Oct 2026, 04:00")
    let text = m.crashReportText
    #expect(text.hasPrefix("JournalInsight crash report"))
    #expect(text.contains("Type: NSInvalidArgumentException"))
    #expect(text.contains("Call stack:\n0 CoreFoundation"))
    #expect(text.contains("\n\n---\n\n"))
    #expect(text.range(of: "NSInvalidArgumentException")!.lowerBound < text.range(of: "SIGSEGV")!.lowerBound)
}

@Test @MainActor func versionCrashReloadPicksUpNewRecordsAndClearEmptiesStore() throws {
    let (m, store) = try makeCrashModel([])
    #expect(m.lastCrash == nil)
    try store.write(CrashRecord(id: "late", date: crashT0, source: .metricKit, appVersion: "2.0.0", build: "42", type: "SIGABRT", summary: "x"))
    #expect(m.lastCrash == nil, "list is a snapshot until reload")
    m.reloadCrashes()
    #expect(m.lastCrash?.id == "late")

    m.clearCrashes()
    #expect(m.crashes.isEmpty)
    #expect(m.lastCrash == nil)
    #expect(m.crashClearError == nil)
    #expect(store.list().isEmpty)
}

@Test @MainActor func versionCrashFixturesRenderBothStates() {
    let names = ScreenRegistry.entries.map(\.name)
    #expect(names.contains("Version") && names.contains("Version crash"))
    #expect(L6Fixtures.emptyCrashStore.list().isEmpty)
    #expect(L6Fixtures.seededCrashStore.list().map(\.id) == ["fixture-exc", "fixture-mxk"])
}
