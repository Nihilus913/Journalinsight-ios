import Foundation
import Testing

/// B-109 guard (in-scheme twin of `scripts/check-pbxproj-sources.sh`): every Swift file under the
/// xcodegen source dirs must be referenced in the committed `project.pbxproj`. A file that is on
/// disk but not in the pbxproj is silently excluded from its target — the build passes and its
/// tests never run. Reads the host checkout via `#filePath` (works on the iOS Simulator).
@Suite struct ProjectMembershipGuardTests {
    private static let sourceDirs = [
        "App", "AppTests", "AppUITests", "Widgets/Sources", "WatchApp/Sources", "WatchApp/Tests",
    ]

    private static func repoRoot(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func everySwiftSourceFileIsInThePbxproj() throws {
        let root = Self.repoRoot()
        let pbxURL = root.appendingPathComponent("JournalInsight.xcodeproj/project.pbxproj")
        let pbx = try String(contentsOf: pbxURL, encoding: .utf8)
        var checked = 0
        var missing: [String] = []
        let fm = FileManager.default
        for dir in Self.sourceDirs {
            let dirURL = root.appendingPathComponent(dir)
            guard let walker = fm.enumerator(at: dirURL, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                checked += 1
                let name = url.lastPathComponent
                if !pbx.contains("path = \(name);") && !pbx.contains("path = \"\(name)\";") {
                    missing.append("\(dir)/…/\(name)")
                }
            }
        }
        #expect(checked > 20, "guard found only \(checked) Swift files under \(root.path) — wrong root?")
        #expect(missing.isEmpty, "not in project.pbxproj (run `xcodegen generate`): \(missing)")
    }
}
