import CryptoKit
import Foundation
import Testing
@testable import JICore

@Test func fixtureCopiesMatchManifest() throws {
    let root = try #require(Bundle.module.resourceURL).appending(path: "Resources")
    let manifest = try String(contentsOf: root.appending(path: "MANIFEST.sha256"), encoding: .utf8)
    var checked = 0
    for line in manifest.split(separator: "\n") {
        let parts = line.split(separator: "  ", maxSplits: 1)
        let (hash, rel) = (String(parts[0]), String(parts[1]))
        let fileURL = root.appending(path: rel)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { Issue.record("missing fixture copy \(rel) — rerun sync_fixtures.py"); continue }
        let data = try Data(contentsOf: fileURL)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(actual == hash, "drift in \(rel) — rerun HealthTraining/scripts/parity/sync_fixtures.py")
        checked += 1
    }
    print("FixtureManifestTests: checked \(checked) of \(manifest.split(separator: "\n").count) manifest entries")
    #expect(checked == 22, "every manifest entry (17 hub-contract + 5 golden) must be present and verified")
}

/// Guards JICore library's own hub-contract fixture copies (`Packages/JICore/Sources/JICore/
/// Fixtures/hub-contract/`, a `Bundle.module` resource of the JICore target itself — see
/// task-8-report.md / task-8-fix-1-report.md) against the same `MANIFEST.sha256` the test
/// target's copy is checked against above. `HealthTraining/scripts/parity/sync_fixtures.py`
/// refreshes both copies from the fixtures of record in the same loop; this test is what would
/// catch the two falling out of sync.
@Test func libraryFixtureCopiesMatchManifest() throws {
    let root = try #require(Bundle.module.resourceURL).appending(path: "Resources")
    let manifest = try String(contentsOf: root.appending(path: "MANIFEST.sha256"), encoding: .utf8)
    var checked = 0
    for line in manifest.split(separator: "\n") {
        let parts = line.split(separator: "  ", maxSplits: 1)
        let (hash, rel) = (String(parts[0]), String(parts[1]))
        guard rel.hasPrefix("hub-contract/") else { continue }
        let name = String(rel.dropFirst("hub-contract/".count).dropLast(".json".count))
        let url = try #require(
            MockDataProvider.fixtureURL(named: name),
            "missing JICore library fixture copy for \(name) — rerun HealthTraining/scripts/parity/sync_fixtures.py"
        )
        let data = try Data(contentsOf: url)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(actual == hash, "JICore library copy of \(name) drifted from MANIFEST.sha256 — rerun HealthTraining/scripts/parity/sync_fixtures.py")
        checked += 1
    }
    #expect(checked == 17)
}
