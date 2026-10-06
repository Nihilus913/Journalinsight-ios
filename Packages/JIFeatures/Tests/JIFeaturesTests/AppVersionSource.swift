import Foundation

// B-131 (W-BUG2): the shipped app version has ONE source — the host app's
// `CFBundleShortVersionString` in `project.yml` (Info.plist is generated from it). Version tests
// read it here instead of hard-coding a release that the next bump makes stale.

/// The repo's `project.yml` text (Tests/JIFeaturesTests/<file> → JIFeatures → Packages → repo root).
func projectYmlText() throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
}

/// Every `CFBundleShortVersionString` value in `project.yml`, in file order (host app first).
func projectBundleVersions() throws -> [String] {
    try projectYmlText().split(separator: "\n").compactMap { line -> String? in
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("CFBundleShortVersionString:") else { return nil }
        let parts = t.split(separator: "\"")
        return parts.count >= 2 ? String(parts[1]) : nil
    }
}

/// The installed app version: the host app's `CFBundleShortVersionString`.
func installedAppVersion() throws -> String {
    guard let first = try projectBundleVersions().first else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return first
}
