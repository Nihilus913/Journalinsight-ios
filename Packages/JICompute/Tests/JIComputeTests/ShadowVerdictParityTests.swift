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
///
/// B-111 (W-BUG1 BUG1-1): the golden now also carries recovery-score cases and Apple nights
/// (`m.source == "apple"`, band reduced to `{status, note, today_ms}` — the fields the gate reads).
/// `ShadowNightFixture` maps an Apple case onto `MorningVitals.apple` so `evaluate` takes the
/// `AppleGate.appleGateInputs` branch, exactly as the hub's evaluate() does.

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
    let m: ShadowNightFixture
    let db: DbFixture
    let dosedDates: [String]
    let debtHours: Double?
    let shadow: ShadowFixture
    let hubVerdict: String

    var testDescription: String { label }
}

/// B-111: one golden night — a Garmin night (`VitalsFixture`) or, with `source == "apple"`,
/// an Apple night whose band status/note/today_ms + previous duration feed `AppleNight`.
struct ShadowNightFixture: Decodable, Sendable {
    struct BandFixture: Decodable, Sendable {
        let status: HrvBandStatus
        let note: String
        let todayMs: Double?
        enum CodingKeys: String, CodingKey { case status, note; case todayMs = "today_ms" }
    }

    /// Garmin night: the shared `VitalsFixture`. Nil on an Apple night (its `hrv` is the band's
    /// float `today_ms`, which the Garmin fixture's Int field does not take, and no gate reads it).
    let garmin: VitalsFixture?
    let source: String?
    let hrvBand: BandFixture?
    let sleepDurationH: Double?
    let prevSleepDurationH: Double?
    let recoveryScore: Int?

    enum CodingKeys: String, CodingKey {
        case source
        case hrvBand = "hrv_band"
        case sleepDurationH = "sleep_duration_h"
        case prevSleepDurationH = "prev_sleep_duration_h"
        case recoveryScore = "recovery_score"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        hrvBand = try c.decodeIfPresent(BandFixture.self, forKey: .hrvBand)
        sleepDurationH = try c.decodeIfPresent(Double.self, forKey: .sleepDurationH)
        prevSleepDurationH = try c.decodeIfPresent(Double.self, forKey: .prevSleepDurationH)
        recoveryScore = try c.decodeIfPresent(Int.self, forKey: .recoveryScore)
        garmin = source == "apple" ? nil : try VitalsFixture(from: decoder)
    }

    var isApple: Bool { source == "apple" }

    /// An Apple night is built the way the on-device engine builds it
    /// (JIHealthKit `JIComputeVerdictEngine`): duration + recovery score + `AppleNight`, no Garmin fields.
    var vitals: MorningVitals {
        if let garmin { return garmin.vitals }
        let b = hrvBand ?? BandFixture(status: .missing, note: "", todayMs: nil)
        let band = HrvBandResult(status: b.status, nBaseline: 0, rollingLn: nil, lowerLn: nil, upperLn: nil,
                                 todayMs: b.todayMs, kiviniemi: false, note: b.note)
        return MorningVitals(sleepDurationH: sleepDurationH, recoveryScore: recoveryScore,
                             apple: AppleNight(hrvBand: band, prevSleepDurationH: prevSleepDurationH))
    }
}

enum ShadowGolden {
    static let file = "shadow_verdict.golden"
    /// sha256 of the HT fixture of record at generation (B-15).
    static let recordSHA256 = "bbf1eff9aa9ccdda1f2c60c26908cc8d4a8cb75384158f4caad79ef00fca4d3b"
    static let cases = GoldenLoader.require(ShadowVerdictCase.self, file: file, group: "shadowVerdictCases")
}

@Suite struct ShadowVerdictParityTests {
    @Test func shadowFixtureIsTheHubFileOfRecord() throws {
        let url = try #require(Bundle.module.url(forResource: ShadowGolden.file, withExtension: "json", subdirectory: "Resources/golden"))
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == ShadowGolden.recordSHA256)
        #expect(ShadowGolden.cases.count >= 30)
    }

    /// B-111: the golden exercises the recovery-score gate and Apple nights (incl. the 2026-10-06
    /// prod E2E record), and every Apple case decodes into an Apple night.
    @Test func shadowGoldenCoversRecoveryAndAppleNights() throws {
        let cases = ShadowGolden.cases
        #expect(cases.contains { $0.label == "fail-recovery-low" && $0.shadow.liveGateOk == false })
        #expect(cases.contains { $0.label == "e2e-2026-10-06-apple-band-amber" && $0.shadow.liveGateOk == false })
        let apple = cases.filter { $0.m.isApple }
        #expect(apple.count >= 10)
        #expect(apple.allSatisfy { $0.m.vitals.apple != nil })
        #expect(apple.contains { $0.shadow.liveGateOk == true })
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
}
