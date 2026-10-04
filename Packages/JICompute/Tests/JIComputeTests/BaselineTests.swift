import Testing
@testable import JICompute

/// W-ONDEVICE O-1: the ONE public baseline primitive (`Baseline`) — `median`, `robustBaseline`
/// (MIN 19 / WINDOW 120 / MAD 1.4826), `trailingZ` — against `readiness.golden.json`
/// (`HealthTraining/scripts/parity/gen_golden_readiness.py`, ground truth
/// `app/vitals/readiness_composite.py`). Bit-exact: every double compares with `==`.

struct MedianCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["values", "expected"]
    let values: [Double]
    let expected: Double
    var testDescription: String { "median n=\(values.count)" }
}

struct RobustBaselineCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["values", "expected"]
    struct Expected: Decodable, Sendable { let median, sd: Double }
    let values: [Double]
    let expected: Expected?
    var testDescription: String { "robustBaseline n=\(values.count) -> \(expected == nil ? "nil" : "value")" }
}

struct TrailingZCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["series", "target", "expected"]
    let series: [String: Double]
    let target: String
    let expected: Double?
    var testDescription: String { "trailingZ \(target) n=\(series.count)" }
}

enum BaselineGolden {
    static let median = GoldenLoader.require(MedianCase.self, file: "readiness.golden", group: "medianCases")
    static let robust = GoldenLoader.require(RobustBaselineCase.self, file: "readiness.golden", group: "robustBaselineCases")
    static let trailing = GoldenLoader.require(TrailingZCase.self, file: "readiness.golden", group: "trailingZCases")
}

@Test func baselineConstantsMatchPython() {
    #expect(Baseline.minDays == 19)
    #expect(Baseline.windowDays == 120)
    #expect(Baseline.madScale == 1.4826)
}

@Test func baselineGoldenCounts() {
    #expect(BaselineGolden.median.count == 38)
    #expect(BaselineGolden.robust.count == 48)
    #expect(BaselineGolden.trailing.count == 50)
}

@Test func medianOddAndEven() {
    #expect(Baseline.median([3, 1, 2]) == 2)
    #expect(Baseline.median([4, 1, 3, 2]) == 2.5)
    #expect(Baseline.median([0.1, 0.2]) == (0.1 + 0.2) / 2)
}

@Test func robustBaselineEdges() {
    #expect(Baseline.robustBaseline((0..<18).map { 40.0 + Double($0) }) == nil)
    let v19 = try? #require(Baseline.robustBaseline((0..<19).map { 40.0 + Double($0) }))
    #expect(v19?.median == 49)
    #expect(v19?.sd == 5 * 1.4826)
    #expect(Baseline.robustBaseline(Array(repeating: 55.0, count: 25)) == nil)  // MAD = 0 -> nil
}

@Test func trailingZExcludesTodayFromItsOwnWindow() throws {
    var s: [String: Double] = [:]
    for i in 0..<18 { s[try CalendarMath.addDays("2026-10-04", -(1 + i))] = 50 + Double(i % 7) }
    s["2026-10-04"] = 1000
    #expect(try Baseline.trailingZ(target: "2026-10-04", series: s) == nil)  // 18 prior, today not counted
    s["2026-09-15"] = 52
    #expect(try Baseline.trailingZ(target: "2026-10-04", series: s) != nil)
}

@Test(arguments: BaselineGolden.median)
func medianMatchesPython(_ c: MedianCase) {
    #expect(Baseline.median(c.values) == c.expected)
}

@Test(arguments: BaselineGolden.robust)
func robustBaselineMatchesPython(_ c: RobustBaselineCase) {
    let got = Baseline.robustBaseline(c.values)
    #expect(got?.median == c.expected?.median)
    #expect(got?.sd == c.expected?.sd)
}

@Test(arguments: BaselineGolden.trailing)
func trailingZMatchesPython(_ c: TrailingZCase) throws {
    #expect(try Baseline.trailingZ(target: c.target, series: c.series) == c.expected)
}
