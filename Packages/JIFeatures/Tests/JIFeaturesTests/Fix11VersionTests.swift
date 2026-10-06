import Foundation
import Testing
@testable import JIFeatures

// W-FIX11 H2-22 (bug hunt 2026-10-01): About showed "2.0.0 · build 1" and "2.0.0 Regression
// fixes · 25 Sep · Installed" after FIX6–FIX10. The installed entry is the release on the bundle.
@Test func theInstalledEntryIsTheBundleVersion() throws {
    // B-131: the bundle version comes from project.yml (its single source), not a literal.
    let versions = try projectBundleVersions()
    let latest = Changelog.swiftEntries[0]
    #expect(versions.count >= 3)                                   // app + Watch + widgets (+ watch widgets)
    #expect(Set(versions) == [latest.version])                      // every bundle = the newest changelog entry
    #expect(latest.date == Changelog.swiftEntries.map(\.date).max())  // and it is the newest by date
    #expect(latest.date >= "2026-10-01")
    #expect(!versions.contains("2.0.0"))
}
