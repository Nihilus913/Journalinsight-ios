import Foundation
import Testing
@testable import JIFeatures

// W-FIX-P3 RG-79 (B-18): "What changed" lists every release merged after the 2.2.0 overnight
// (B-52, B-91, B-99, B-94, B-90, B-95, B-89, B-44od) in a 2.2.1 entry, which leads the list so the
// About screen's "Installed" badge marks it; the board line keeps the build number.

@Suite struct FixP3ChangelogTests {
    @Test func newestEntryIs221AndLeads() {
        #expect(Changelog.swiftEntries.first == Changelog.waveThreeEntry)
        #expect(Changelog.waveThreeEntry.version == "2.2.1")
        #expect(Set(Changelog.entries.map(\.version)).count == Changelog.entries.count)   // ids stay unique
    }

    @Test func entryNamesTheEightMergedReleases() {
        let text = Changelog.waveThreeEntry.items.joined(separator: "\n")
        // one keyword per backlog row: B-52 offline, B-91 strain, B-99 diet quality, B-94 progress
        // charts, B-90 muscle load, B-95 time in zone, B-89 personal records, B-44od on-device verdict
        for key in ["offline", "Strain", "Diet quality", "Progress charts", "Muscle load", "time in each heart-rate zone",
                    "Personal records", "on this phone"] {
            #expect(text.contains(key), "missing \(key)")
        }
        #expect(Changelog.waveThreeEntry.items.count == 8)
    }

    @Test func installedRowMarks221AndShowsBuild() {
        let info = VersionInfo(appName: "JournalInsight", appVersion: "2.2.1", build: "2610060900", bundleId: "toby913.JournalInsight")
        let rows = versionHighlights(Changelog.entries, appVersion: info.appVersion)
        #expect(rows.first?.installed == true)
        #expect(rows.filter(\.installed).count == 1)
    }
}
