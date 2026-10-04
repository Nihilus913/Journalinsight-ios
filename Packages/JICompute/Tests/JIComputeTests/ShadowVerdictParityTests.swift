import CryptoKit
import Foundation
import Testing
@testable import JICompute

/// B-15 (HT card docs/waves/cards/2610-b15.md): the on-device verdict (`evaluate`, the gate B-44
/// switches to from 2026-10-05) run against the SAME fixed mornings the hub's golden test
/// locks `compute_shadow_verdict()` and `evaluate()` to.
///
/// `Resources/golden/shadow_verdict.golden.json` is a byte copy of HealthTraining
/// `mobile/__tests__/compute/golden/shadow_verdict.golden.json` (generator
/// `scripts/parity/gen_golden_shadow.py`, pytest `tests/test_shadow_verdict_golden.py`).
/// Never edit it here; the sha256 below pins the copy to the HT file of record.
///
/// Per case: the Swift verdict string == the hub verdict byte-exact, and on interval days the
/// Swift gate (GO or not) == the hub shadow's reconstructed `live_gate_ok`. The shadow-only
/// cap lift (`shadow_gate_ok`) is NOT ported: the on-device gate is the LIVE gate.

struct ShadowFixture: Decodable, Sendable {
    let applicable: Bool
    let shadowVerdict: String?
    let liveGateOk: Bool?
    let shadowGateOk: Bool?
    let diverges: Bool
    let note: String

    enum CodingKeys: String, CodingKey {
        case applicable, diverges, note
        case shadowVerdict = "shadow_verdict"
        case liveGateOk = "live_gate_ok"
        case shadowGateOk = "shadow_gate_ok"
    }
}

struct ShadowVerdictCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["label", "today", "m", "db", "dosedDates", "debtHours", "shadow", "hubVerdict"]

    let label: String
    let today: String
    let m: VitalsFixture
    let db: DbFixture
    let dosedDates: [String]
    let debtHours: Double?
    let shadow: ShadowFixture
    let hubVerdict: String

    var testDescription: String { label }
}

enum ShadowGolden {
    static let file = "shadow_verdict.golden"
    /// sha256 of the HT fixture of record at generation (B-15).
    static let recordSHA256 = "de63b1a8960838e09a7f170cf00f50b2cde2afc8e56c88259892a00c1752c857"
    static let cases = GoldenLoader.require(ShadowVerdictCase.self, file: file, group: "shadowVerdictCases")
}

@Test func shadowFixtureIsTheHubFileOfRecord() throws {
    let url = try #require(Bundle.module.url(forResource: ShadowGolden.file, withExtension: "json", subdirectory: "Resources/golden"))
    let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    #expect(digest == ShadowGolden.recordSHA256)
    #expect(ShadowGolden.cases.count >= 30)
}

@Test(arguments: ShadowGolden.cases)
func onDeviceVerdictMatchesHubOnShadowGolden(_ c: ShadowVerdictCase) throws {
    let got = try evaluate(
        today: c.today,
        vitals: c.m.vitals,
        db: c.db.db(lifts: []),
        state: MorningGatePrevState(),
        dosedDates: c.dosedDates,
        config: .default
    )
    #expect(got.verdict == c.hubVerdict, "verdict: got \"\(got.verdict)\", want \"\(c.hubVerdict)\"")
    if c.shadow.applicable {
        let liveGateOk = try #require(c.shadow.liveGateOk)
        #expect(got.verdict.hasPrefix("GO — ") == liveGateOk, "on-device gate != hub live_gate_ok")
    }
}
