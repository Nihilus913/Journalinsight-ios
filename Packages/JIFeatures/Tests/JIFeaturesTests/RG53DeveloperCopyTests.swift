import Foundation
import Testing
@testable import JIFeatures

/// W-FIX-P2 RG-53 (B-44od): the Developer copy describes the post-B-44od behaviour — the phone
/// computes the verdict, the hub is the oracle — and never the retired shadow mode.
@Suite struct RG53DeveloperCopyTests {
    private static let retired = ["Shadow run", "stay on the hub", "not available on Apple Watch until"]

    @Test func copyNamesThePhoneAndTheHubOracle() {
        #expect(DeveloperVerdictCopy.gateNote.contains("this iPhone"))
        #expect(DeveloperVerdictCopy.gateNote.contains("oracle"))
        #expect(DeveloperVerdictCopy.onDeviceToggleSubtitle.contains("oracle"))
        for s in Self.retired {
            #expect(!DeveloperVerdictCopy.gateNote.contains(s))
            #expect(!DeveloperVerdictCopy.onDeviceToggleSubtitle.contains(s))
        }
    }

    /// grep-style: the retired strings are absent from both Settings sources.
    @Test func retiredStringsAbsentFromSources() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JIFeatures/Settings/Sections")
        for name in ["ProviderSection.swift", "OnDeviceVerdictSection.swift"] {
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            for s in Self.retired { #expect(!text.contains(s), "\(name) still says '\(s)'") }
        }
    }
}
