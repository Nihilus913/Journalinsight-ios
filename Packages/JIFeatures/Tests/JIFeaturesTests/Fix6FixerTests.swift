import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-FIX6 fixer: verifier misses — F6-11 detail (no lift weight on a cardio session) and
/// V-37 (Apple Health "Backload to Apple Health" was a green text link).
@MainActor
struct Fix6FixerTests {
    static let lift = LiftProgression(exerciseId: 1, name: "Bench press", sessionName: "Day 1 Full Upper",
                                      currentKg: 50, nextKg: 50, state: .notYet, sets: 3)

    @Test(arguments: ["Long Zone 2 75-90min", "Long Z2", "Norwegian 4x4 intervals", "Z2 40min", "Easy run"])
    func cardioSessionHidesTheLiftWeight(session: String) {
        let go = verdictParts("GO — \(session)")
        #expect(decideSessionLiftShown(verdict: go, sessionDetail: session, lifts: [Self.lift]) == nil)
    }

    @Test(arguments: ["Full Upper", "Day 1 Full Upper + Z2 40min", "Day 3 Full Upper + Z2 60min", "Strength"])
    func strengthSessionKeepsTheLiftWeight(session: String) {
        let go = verdictParts("GO (auto-regulated) — Day 1 Full Upper + Z2 40min")
        #expect(decideSessionLiftShown(verdict: go, sessionDetail: session, lifts: [Self.lift])?.kg == "50.0 kg")
    }

    @Test func backloadIsAPrimaryButtonNotATextLink() throws {
        let pkg = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let body = try String(contentsOf: pkg.appending(path: "Sources/JIFeatures/Settings/HealthBackloadSection.swift"),
                              encoding: .utf8)
        let hit = try #require(body.range(of: "\"Backload to Apple Health\""))
        let window = String(body[hit.upperBound...].prefix(250))
        #expect(window.contains(".buttonStyle(.jiPrimary)") || window.contains(".buttonStyle(.jiSecondary)"),
                "Backload to Apple Health is a bare text link")
    }
}
