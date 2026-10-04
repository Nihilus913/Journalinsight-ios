import Foundation
import Testing
@testable import JICompute

/// W-ONDEVICE O-4: the Apple branch of the gate against `morning_apple.golden.json`
/// (`HealthTraining/scripts/parity/gen_golden_morning_apple.py`, ground truth `scripts/morning_go.py`
/// `apple_gate_inputs` / `gate_signals` / `evaluate` with the band from `hrv_band.py`). Each case
/// builds the band from the raw nightly series with `HrvBand.compute`, then checks the gate inputs,
/// every signal row and the full verdict + conditions + new state byte-for-byte.

struct AppleGateConstants: Decodable, Sendable {
    let appleMinSleepH, appleSleepRedH: Double
    let recoveryLowScore, recoveryNightsNeeded: Int
    let hrvBandMethod: String
}

struct AppleGateCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = [
        "label", "today", "apple", "garmin", "sleepDurationH", "prevSleepDurationH", "recoveryAttached", "recovery",
        "hrvDay", "contextRhr", "contextSleepScore", "sleepGoalH", "state", "dosedDates", "bandStatus",
        "red", "amber", "ok", "signals", "verdict", "conditions", "newState",
    ]
    struct Rec: Decodable, Sendable { let status: String; let score: Int?; let nights, nApple, nGarmin: Int }
    struct HrvDay: Decodable, Sendable { let value, baseline: Double?; let dosed_proxy: Bool }
    struct State: Decodable, Sendable { let hrv_low, rhr_high, sleep_low: Bool?; let hrv_low_n: Int?; let rhr_date: String? }
    struct NewState: Decodable, Sendable {
        let date: String; let hrv_low, rhr_high, sleep_low: Bool; let hrv_low_n: Int; let rhr_date: String?
    }
    struct Signal: Decodable, Sendable {
        let key, label, unit, direction, status, note: String
        let value, threshold: Double?
        let scale_min, scale_max: Double
        let calibrating: Bool?
        let nights, nights_needed, band_lo, band_hi: Int?
        let band_method: String?
    }
    let label, today, bandStatus, verdict: String
    let apple: [String: Double]
    let garmin: [String: Double]?
    let sleepDurationH, prevSleepDurationH, contextRhr, contextSleepScore, sleepGoalH: Double?
    let recoveryAttached: Bool
    let recovery: Rec?
    let hrvDay: HrvDay?
    let state: State
    let dosedDates: [String]
    let red, amber, conditions: [String]
    let ok: Bool
    let signals: [Signal]
    let newState: NewState
    var testDescription: String { "\(label) -> \(verdict)" }

    var recoveryResult: RecoveryScoreResult? {
        recovery.map {
            RecoveryScoreResult(status: RecoveryScoreStatus(rawValue: $0.status)!, score: $0.score, raw: $0.score.map(Double.init),
                                components: [], nights: $0.nights, nApple: $0.nApple, nGarmin: $0.nGarmin)
        }
    }

    func vitals() throws -> MorningVitals {
        let band = try HrvBand.compute(apple: apple, today: today, garmin: garmin)
        let night = AppleNight(hrvBand: band, prevSleepDurationH: prevSleepDurationH,
                               hrvDay: hrvDay.map { AppleHrvDay(value: $0.value, baseline: $0.baseline, dosedProxy: $0.dosed_proxy) },
                               contextRhr: contextRhr, contextSleepScore: contextSleepScore)
        return MorningVitals(sleepDurationH: sleepDurationH, recoveryScore: recovery?.score, apple: night)
    }
}

enum AppleGateGolden {
    static let file = "morning_apple.golden"
    static let cases = GoldenLoader.require(AppleGateCase.self, file: file, group: "appleCases")
    static let constants: AppleGateConstants = {
        struct File: Decodable { let constants: AppleGateConstants }
        let url = Bundle.module.url(forResource: file, withExtension: "json", subdirectory: "Resources/golden")!
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url)).constants
    }()
}

@Test func appleGateConstantsMatchPython() {
    let c = AppleGateGolden.constants
    #expect(c.appleMinSleepH == AppleGate.appleMinSleepH && c.appleSleepRedH == AppleGate.appleSleepRedH)
    #expect(c.recoveryLowScore == MorningGateConfig.default.recoveryLowScore && c.recoveryLowScore == RecoveryScore.lowScore)
    #expect(c.hrvBandMethod == AppleGate.hrvBandMethod && c.recoveryNightsNeeded == PersonalNormal.minN)
}

@Test func appleGateGoldenCount() {
    #expect(AppleGateGolden.cases.count == 56)
    let verdicts = Set(AppleGateGolden.cases.map { String($0.verdict.prefix(3)) })
    #expect(verdicts.isSuperset(of: ["GO ", "MOD", "RED", "RES"]))     // go / modify / reduced / rest all covered
}

/// The exit grep: the gate file itself carries the Apple branch.
@Test func morningGateGateHasTheAppleBranch() throws {
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JICompute/MorningGate/MorningGateGate.swift")
    let text = try String(contentsOf: path, encoding: .utf8)
    #expect(text.range(of: "apple", options: .caseInsensitive) != nil)
}

@Test(arguments: AppleGateGolden.cases)
func appleGateMatchesPython(_ c: AppleGateCase) throws {
    let m = try c.vitals()
    #expect(m.apple?.hrvBand.status.rawValue == c.bandStatus)

    let inputs = try #require(AppleGate.appleGateInputs(m))
    #expect(inputs.red == c.red)
    #expect(inputs.amber == c.amber)
    #expect(inputs.ok == c.ok)

    let rec: RecoverySignalInput = c.recoveryAttached ? .attached(c.recoveryResult) : .notAttached
    let got = AppleGate.gateSignals(m, recovery: rec, sleepGoalH: c.sleepGoalH)
    #expect(got.count == c.signals.count, "\(got.map(\.key)) vs \(c.signals.map(\.key))")
    for (g, e) in zip(got, c.signals) {
        #expect(g.key == e.key && g.label == e.label && g.unit == e.unit && g.direction == e.direction)
        #expect(g.status == e.status, "\(e.key)")
        #expect(g.note == e.note, "\(e.key)")
        #expect(g.value == e.value && g.threshold == e.threshold, "\(e.key) value/threshold")
        #expect(g.scaleMin == e.scale_min && g.scaleMax == e.scale_max)
        #expect(g.calibrating == e.calibrating && g.nights == e.nights && g.nightsNeeded == e.nights_needed)
        #expect(g.bandLo == e.band_lo && g.bandHi == e.band_hi && g.bandMethod == e.band_method)
    }

    let state = MorningGatePrevState(hrvLow: c.state.hrv_low, rhrHigh: c.state.rhr_high, rhrDate: c.state.rhr_date,
                                     sleepLow: c.state.sleep_low, hrvLowN: c.state.hrv_low_n)
    let r = try evaluate(today: c.today, vitals: m, db: MorningGateDb(), state: state, dosedDates: c.dosedDates)
    #expect(r.verdict == c.verdict)
    #expect(r.conditions == c.conditions)
    let n = c.newState
    #expect(r.newState == MorningGateNewState(date: n.date, hrvLow: n.hrv_low, rhrHigh: n.rhr_high, rhrDate: n.rhr_date,
                                              sleepLow: n.sleep_low, hrvLowN: n.hrv_low_n))
}

@Test(arguments: [(7.0, "7"), (6.0, "6"), (7.5, "7.5"), (41.2, "41.2"), (54.0, "54"), (57.5, "57.5"),
                  (44.0, "44"), (0.5, "0.5"), (123.456789, "123.457"), (9.9999996, "10"), (0.00123, "0.00123")])
func pythonGFormat(_ c: (Double, String)) {
    #expect(AppleGate.g(c.0) == c.1)
}
