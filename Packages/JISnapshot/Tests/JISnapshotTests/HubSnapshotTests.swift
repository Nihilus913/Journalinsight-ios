import Foundation
import Testing
@testable import JISnapshot

@Suite
struct HubSnapshotTests {
    static func makeSnapshot() -> HubSnapshot {
        HubSnapshot(
            verdictWord: "GO",
            verdictSession: "Full session",
            verdictTone: "go",
            verdictDate: "2026-09-13",
            readiness: 82.5,
            kpis: [
                SnapshotKPI(label: "HRV", value: 61.0, unit: "ms"),
                SnapshotKPI(label: "RHR", value: 48.0, unit: "bpm"),
                SnapshotKPI(label: "Sleep", value: nil, unit: nil),
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_757_000_000),
            lastSync: Date(timeIntervalSince1970: 1_756_999_000)
        )
    }

    @Test
    func codableRoundTrip() throws {
        let snapshot = Self.makeSnapshot()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(HubSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test
    func hasNoSecretField() {
        let mirror = Mirror(reflecting: Self.makeSnapshot())
        let labels = mirror.children.compactMap { $0.label?.lowercased() }
        #expect(!labels.isEmpty)
        for label in labels {
            #expect(!label.contains("token"))
            #expect(!label.contains("secret"))
            #expect(!label.contains("password"))
            #expect(!label.contains("credential"))
        }
    }
}
