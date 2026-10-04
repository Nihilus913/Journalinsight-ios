import Foundation
import Testing
@testable import JICompute

/// W-ONDEVICE O-2: `HrvBand` against `hrvband.golden.json` (`HealthTraining/scripts/parity/
/// gen_golden_hrvband.py`, ground truth `app/vitals/hrv_band.py` @ cal). Bit-exact: CPython's
/// `statistics.mean`/`stdev` are exact-rational + correctly rounded, so is `PythonStatistics`;
/// every double compares with `==`, status / note / counts byte-equal.

struct HrvBandConstants: Decodable, Sendable {
    let baselineNights, rollingNights, minDualNights: Int
    let swcFactor, garminRmssdFactor: Double
}

struct HrvNoteCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["nApple", "nGarmin", "note"]
    let nApple, nGarmin: Int
    let note: String
    var testDescription: String { "note \(nApple)+\(nGarmin)" }
}

struct HrvFitCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["apple", "garmin", "expected"]
    let apple, garmin: [String: Double]
    let expected: Double
    var testDescription: String { "fit apple=\(apple.count) -> \(expected)" }
}

struct HrvCombineCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["apple", "garmin", "factor", "values", "source"]
    let apple, garmin, values: [String: Double]
    let factor: Double?
    let source: [String: String]
    var testDescription: String { "combine apple=\(apple.count) garmin=\(garmin.count)" }
}

struct HrvBandCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["label", "apple", "garmin", "factor", "today", "expected"]
    struct Expected: Decodable, Sendable {
        let status: String
        let n_baseline: Int
        let rolling_ln, lower_ln, upper_ln, today_ms: Double?
        let kiviniemi: Bool
        let note: String
        let calibrating: Bool
        let n_apple, n_garmin: Int
    }
    let label: String
    let apple: [String: Double]
    let garmin: [String: Double]?
    let factor: Double?
    let today: String
    let expected: Expected
    var testDescription: String { "\(label) -> \(expected.status)" }
}

enum HrvBandGolden {
    static let file = "hrvband.golden"
    static let notes = GoldenLoader.require(HrvNoteCase.self, file: file, group: "noteCases")
    static let fit = GoldenLoader.require(HrvFitCase.self, file: file, group: "fitFactorCases")
    static let combine = GoldenLoader.require(HrvCombineCase.self, file: file, group: "combineCases")
    static let band = GoldenLoader.require(HrvBandCase.self, file: file, group: "bandCases")
    static let constants: HrvBandConstants = {
        struct File: Decodable { let constants: HrvBandConstants }
        let url = Bundle.module.url(forResource: file, withExtension: "json", subdirectory: "Resources/golden")!
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url)).constants
    }()
}

@Test func pythonStatisticsIsExact() {
    #expect(PythonStatistics.mean(Array(repeating: 0.1, count: 10)) == 0.1)        // naive sum gives 0.09999…
    #expect(PythonStatistics.mean(Array(repeating: log(50.0), count: 28)) == log(50.0))
    #expect(PythonStatistics.stdev([1.5, 2.5, 2.5, 2.75, 3.25, 4.75]) == 1.0810874155219827)  // CPython docstring
    #expect(PythonStatistics.stdev(Array(repeating: 3.9, count: 28)) == 0)
    #expect(PythonStatistics.mean([1e16, 1, -1e16]) == 1.0 / 3.0)
}

@Test func hrvBandConstantsMatchPython() {
    let c = HrvBandGolden.constants
    #expect(c.baselineNights == HrvBand.baselineNights && c.rollingNights == HrvBand.rollingNights)
    #expect(c.minDualNights == HrvBand.minDualNights && c.swcFactor == HrvBand.swcFactor)
    #expect(c.garminRmssdFactor == HrvBand.garminRmssdFactor)
}

@Test func hrvBandGoldenCounts() {
    #expect(HrvBandGolden.notes.count == 5)
    #expect(HrvBandGolden.fit.count == 20)
    #expect(HrvBandGolden.combine.count == 15)
    #expect(HrvBandGolden.band.count == 89)
}

@Test(arguments: HrvBandGolden.notes)
func hrvCalibratingNoteMatchesPython(_ c: HrvNoteCase) {
    #expect(HrvBand.calibratingNote(nApple: c.nApple, nGarmin: c.nGarmin) == c.note)
}

@Test(arguments: HrvBandGolden.fit)
func hrvFitDeviceFactorMatchesPython(_ c: HrvFitCase) {
    #expect(HrvBand.fitDeviceFactor(apple: c.apple, garmin: c.garmin) == c.expected)
}

@Test(arguments: HrvBandGolden.combine)
func hrvCombineNightlyMatchesPython(_ c: HrvCombineCase) {
    let (values, source) = HrvBand.combineNightly(apple: c.apple, garmin: c.garmin, factor: c.factor)
    #expect(values == c.values)
    #expect(source.mapValues(\.rawValue) == c.source)
}

@Test(arguments: HrvBandGolden.band)
func hrvBandMatchesPython(_ c: HrvBandCase) throws {
    let r = try HrvBand.compute(apple: c.apple, today: c.today, garmin: c.garmin, factor: c.factor)
    let e = c.expected
    #expect(r.status.rawValue == e.status)
    #expect(r.note == e.note)
    #expect(r.nBaseline == e.n_baseline && r.nApple == e.n_apple && r.nGarmin == e.n_garmin)
    #expect(r.kiviniemi == e.kiviniemi && r.calibrating == e.calibrating)
    #expect(r.rollingLn == e.rolling_ln && r.lowerLn == e.lower_ln && r.upperLn == e.upper_ln)
    #expect(r.todayMs == e.today_ms)
}
