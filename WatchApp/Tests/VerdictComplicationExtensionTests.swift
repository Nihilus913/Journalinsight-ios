import Foundation
import Testing
import JISnapshot
@testable import WatchApp

/// W-BUG1 BUG1-3 (B-130): the complication lives in its own watchOS widget extension, a separate
/// process with its OWN `UserDefaults.standard`. What W-B78 stores on receive must therefore be
/// readable through the watch-local App Group, or the extension's timeline stays a placeholder.
@Suite
struct VerdictComplicationExtensionTests {
    private static func defaults(_ tag: String) -> (UserDefaults, String) {
        let name = "bug1-l2.\(tag).\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test @MainActor
    func appliedSnapshotReachesAnExtensionProcessWithItsOwnDefaults() throws {
        let (appLocal, _) = Self.defaults("app")
        let (_, groupName) = Self.defaults("group")
        let (extensionLocal, _) = Self.defaults("ext")
        var reloads = 0
        let store = WatchSnapshotStore(suiteName: groupName, local: appLocal, reloadTimelines: { reloads += 1 })
        let wire = try #require(WatchSnapshotStore.debugFakeSnapshotData(environment: ["WATCH_FAKE_SNAPSHOT": "1"]))
        #expect(store.apply(wire))
        #expect(reloads == 1)

        let provider = VerdictComplicationProvider(suiteName: groupName, local: extensionLocal)
        let entry = try #require(provider.currentEntries().first)
        #expect(entry.verdictWord == "GO")
        #expect(entry.tone == "go")
    }

    @Test
    func extensionWithoutAnyStoredSnapshotShowsThePlaceholder() throws {
        let (_, groupName) = Self.defaults("group")
        let (extensionLocal, _) = Self.defaults("ext")
        let provider = VerdictComplicationProvider(suiteName: groupName, local: extensionLocal)
        let entry = try #require(provider.currentEntries().first)
        #expect(entry.verdictWord == "—")
        #expect(entry.tone == "muted")
    }
}
