import Foundation
import Testing
@testable import JICompute

/// B-91 S3 (b91p1) parity: `strain.golden.json` is a byte-copy of HT
/// `tests/fixtures/strain.golden.json` (ground truth `app/vitals/strain.py` `strain_summary`).
/// Every double compares within 1e-9 (card exit check); ints, status and dates with `==`.
/// Never edit the fixture here — regenerate it in HT and copy it over.

struct StrainGoldenCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["name", "today", "loads", "expected"]
    struct Day: Decodable, Sendable { let date: String; let value: Double? }
    struct Expected: Decodable, Sendable {
        let status: String
        let loaded_days, min_loaded_days, window_days: Int
        let ceiling: Double?
        let usual_low, usual_high: Int?
        let yesterday, today: Day
    }
    let name: String
    let today: String
    let loads: [String: Double]
    let expected: Expected
    var testDescription: String { name }
}

private func close(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (x?, y?): abs(x - y) <= 1e-9
    default: false
    }
}

@Suite struct StrainGoldenTests {
    static let cases = GoldenLoader.require(StrainGoldenCase.self, file: "strain.golden", group: "cases")

    @Test func strainGoldenCount() {
        #expect(Self.cases.count == 3)
    }

    @Test(arguments: StrainGoldenTests.cases)
    func strainSummaryMatchesPython(_ c: StrainGoldenCase) throws {
        let s = try Strain.summary(loads: c.loads, today: c.today)
        let e = c.expected
        #expect(s.status.rawValue == e.status)
        #expect(s.loadedDays == e.loaded_days)
        #expect(s.minLoadedDays == e.min_loaded_days)
        #expect(s.windowDays == e.window_days)
        #expect(close(s.ceiling, e.ceiling), "ceiling \(String(describing: s.ceiling)) vs \(String(describing: e.ceiling))")
        #expect(s.usualLow == e.usual_low)
        #expect(s.usualHigh == e.usual_high)
        #expect(s.yesterday.date == e.yesterday.date)
        #expect(close(s.yesterday.value, e.yesterday.value), "yesterday \(String(describing: s.yesterday.value)) vs \(String(describing: e.yesterday.value))")
        #expect(s.today.date == e.today.date)
        #expect(close(s.today.value, e.today.value), "today \(String(describing: s.today.value)) vs \(String(describing: e.today.value))")
    }

    @Test func percentileIsLinearInterpolation() {
        #expect(close(Strain.percentile([1, 2, 3, 4], 0.9), 3.7))
        #expect(Strain.percentile([5], 0.25) == 5)
        #expect(close(Strain.percentile([4, 1, 3, 2], 0.5), 2.5))
        #expect(Strain.percentile([], 0.5) == nil)
    }

    @Test func strainCurveSaturatesAndIsZeroWithoutLoad() {
        #expect(Strain.strainFromLoad(0, ceiling: 3.7) == 0.0)
        #expect(Strain.strainFromLoad(3.7, ceiling: 3.7) == 63.2)
        #expect(Strain.strainFromLoad(1000, ceiling: 3.7) == 100.0)
        #expect(Strain.strainFromLoad(2, ceiling: 0) == 0.0)
    }

    @Test func registeredAsComputedParityPort() {
        #expect(ParityRegistry.source(for: Strain.registryKey) == .computed)
        #expect(ParityRegistry.implementation(for: Strain.registryKey) == "JICompute.Strain")
    }
}
