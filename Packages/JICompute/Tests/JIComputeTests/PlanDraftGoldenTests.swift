import Foundation
import Testing
@testable import JICompute

// W-B101 B101-3 (BP-21 S1): the hub-less twin of HT app/planning/plan_draft.py. The golden file is a
// byte copy of HT tests/fixtures/plan_draft/plan_draft.golden.json (hand-authored there; never edit here).

private struct GoldenFile: Decodable {
    struct Expected: Decodable, Equatable { let id: String; let status: String; let value: Int? }
    struct Case: Decodable { let name: String; let draft: PlanDraft; let rules: PlanRules; let expected: [Expected] }
    let cases: [Case]
}

private func loadCases() -> [GoldenFile.Case] {
    guard let url = Bundle.module.url(forResource: "plan_draft.golden", withExtension: "json",
                                      subdirectory: "Resources/plan_draft") else {
        fatalError("plan_draft.golden.json is not in the test bundle")
    }
    do { return try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: url)).cases }
    catch { fatalError("plan_draft golden failed to decode: \(error)") }
}

private let cases = loadCases()

struct PlanDraftGoldenTests {
    @Test func goldenHasEveryCase() { #expect(cases.count >= 14) }

    @Test(arguments: cases.map(\.name))
    func golden(_ name: String) throws {
        let c = try #require(cases.first { $0.name == name })
        let got = validatePlanDraft(c.draft, rules: c.rules)
            .map { GoldenFile.Expected(id: $0.id.rawValue, status: $0.status.rawValue, value: $0.value) }
        #expect(got == c.expected)
    }

    @Test func heldDetailNamesTheLoadRatio() throws {
        let c = try #require(cases.first { $0.name == "mockup_4wk_held_acwr_1_84" })
        let checks = validatePlanDraft(c.draft, rules: c.rules)
        #expect(checks.map(\.id) == PlanCheckID.allCases)
        #expect(checks.last?.detail.contains("1.84") == true)
    }

    @Test func unknownKindFailsToDecode() {
        let json = #"{"baseline_minutes":null,"weeks":[{"days":[{"weekday":0,"sessions":[{"kind":"hiit","minutes":20,"targets":[]}]}]}]}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(PlanDraft.self, from: Data(json.utf8)) }
    }
}
