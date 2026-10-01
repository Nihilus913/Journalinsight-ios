import Foundation
import Testing
@testable import JIFeatures

// W-FIX11 H2-22 (bug hunt 2026-10-01): About showed "2.0.0 · build 1" and "2.0.0 Regression
// fixes · 25 Sep · Installed" after FIX6–FIX10. The installed entry is the release on the bundle.
@Test func theInstalledEntryIsTheBundleVersion() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let yml = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
    let latest = Changelog.swiftEntries[0]
    #expect(latest.version == "2.1.0" && latest.date == "2026-10-01")
    #expect(yml.components(separatedBy: "CFBundleShortVersionString: \"\(latest.version)\"").count - 1 == 3)
    #expect(!yml.contains("CFBundleShortVersionString: \"2.0.0\""))
}
