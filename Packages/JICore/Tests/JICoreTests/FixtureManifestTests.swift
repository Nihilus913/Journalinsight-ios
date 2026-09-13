import CryptoKit
import Foundation
import Testing

@Test func fixtureCopiesMatchManifest() throws {
    let root = try #require(Bundle.module.resourceURL).appending(path: "Resources")
    let manifest = try String(contentsOf: root.appending(path: "MANIFEST.sha256"), encoding: .utf8)
    var checked = 0
    for line in manifest.split(separator: "\n") {
        let parts = line.split(separator: "  ", maxSplits: 1)
        let (hash, rel) = (String(parts[0]), String(parts[1]))
        let fileURL = root.appending(path: rel)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
        let data = try Data(contentsOf: fileURL)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(actual == hash, "drift in \(rel) — rerun HealthTraining/scripts/parity/sync_fixtures.py")
        checked += 1
    }
    print("FixtureManifestTests: checked \(checked) of \(manifest.split(separator: "\n").count) manifest entries")
    #expect(checked >= 17, "must at minimum verify all 17 hub-contract fixtures")
}
