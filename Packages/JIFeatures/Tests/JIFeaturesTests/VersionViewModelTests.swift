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
    #expect(all.first?.id == Changelog.swiftNativeEntry.id)
    #expect(all.first?.title.contains("Swift native") == true)
    #expect(Array(all.dropFirst()) == Changelog.rnEntries)
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
    #expect(m.entries.count == 28)
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
