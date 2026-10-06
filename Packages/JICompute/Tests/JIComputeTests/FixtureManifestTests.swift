import CryptoKit
import Foundation
import Testing

/// B-113 (W-BUG1 BUG1-2): the repo-root `Fixtures/MANIFEST.sha256` pins every fixture copy,
/// including the two shadow fixtures the safety-critical verdict tests read in place:
/// `../Packages/JICompute/.../golden/shadow_verdict.golden.json` (byte copy of the HT file of
/// record) and `../Packages/JIHealthKit/.../rg06_shadow_fixtures.json` (XC-local). Paths are
/// relative to `Fixtures/`. HealthTraining `scripts/parity/sync_fixtures.py` rewrites the
/// manifest and re-hashes the `../` entries; any drift between a file and its entry fails here.
@Suite struct FixtureManifestTests {
    /// `<repo>/Packages/JICompute/Tests/JIComputeTests/FixtureManifestTests.swift` -> `<repo>`.
    static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u = u.deletingLastPathComponent() }
        return u
    }()
    static let fixturesDir = repoRoot.appending(path: "Fixtures")

    static let shadowEntries = [
        "../Packages/JICompute/Tests/JIComputeTests/Resources/golden/shadow_verdict.golden.json",
        "../Packages/JIHealthKit/Tests/JIHealthKitTests/Fixtures/rg06_shadow/rg06_shadow_fixtures.json",
    ]

    struct Entry: Equatable { let hash: String; let path: String }

    static func parse(_ manifest: String) -> [Entry] {
        manifest.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "  ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Entry(hash: String(parts[0]), path: String(parts[1]))
        }
    }

    static func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    /// Manifest paths (relative to `base`) whose file is missing or whose sha256 differs.
    static func mismatches(_ entries: [Entry], base: URL) -> [String] {
        entries.compactMap { e in
            let url = base.appending(path: e.path).standardizedFileURL
            guard let actual = try? sha256(url) else { return "\(e.path) (missing)" }
            return actual == e.hash ? nil : "\(e.path) (sha256 \(actual) != manifest \(e.hash))"
        }
    }

    static func manifest() throws -> [Entry] {
        parse(try String(contentsOf: fixturesDir.appending(path: "MANIFEST.sha256"), encoding: .utf8))
    }

    @Test func everyManifestEntryMatchesItsFile() throws {
        let entries = try Self.manifest()
        #expect(entries.count >= 26, "manifest lost entries: \(entries.count)")
        let bad = Self.mismatches(entries, base: Self.fixturesDir)
        #expect(bad.isEmpty, "fixture drift — rerun HealthTraining/scripts/parity/sync_fixtures.py: \(bad)")
    }

    @Test func shadowFixturesArePinned() throws {
        let paths = Set(try Self.manifest().map(\.path))
        for p in Self.shadowEntries { #expect(paths.contains(p), "MANIFEST.sha256 has no entry for \(p)") }
    }

    /// The check is not vacuous: one flipped byte in a scratch copy is reported.
    @Test func flippedByteInScratchCopyFails() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "FixtureManifestTests-\(UUID().uuidString)")
        let fixtures = scratch.appending(path: "Fixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let entries = try Self.manifest().filter { Self.shadowEntries.contains($0.path) }
        try #require(entries.count == Self.shadowEntries.count)
        for e in entries {
            let dst = fixtures.appending(path: e.path).standardizedFileURL
            try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: Self.fixturesDir.appending(path: e.path).standardizedFileURL, to: dst)
        }
        #expect(Self.mismatches(entries, base: fixtures).isEmpty)

        let victim = fixtures.appending(path: entries[0].path).standardizedFileURL
        var data = try Data(contentsOf: victim)
        data[data.count / 2] ^= 0x01
        try data.write(to: victim)
        let bad = Self.mismatches(entries, base: fixtures)
        #expect(bad.count == 1 && bad[0].hasPrefix(entries[0].path))
    }
}
