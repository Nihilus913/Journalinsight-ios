import Foundation
import Testing
@testable import JICompute

/// W-ONDEVICE O-5 (B-19): `ReadinessComposite` on the O-1 `Baseline` primitive against
/// `readiness.golden.json` (ground truth `app/vitals/readiness_composite.py`). Ordinal parity is
/// the contract (the category per day); the composite double is checked too since it is pure
/// arithmetic. `syntheticHistories` = 3 x 30 days, >= 20 of them categorised (O-5 exit).

struct ReadinessConstants: Decodable, Sendable {
    let minDays, windowDays: Int
    let madScale, wHrv, wRhr, wSleep, wLoad, sleepCenter, sleepSpread, high, low: Double
}

struct Load7SessionCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["daily", "target", "expected"]
    let daily: [String: Double]
    let target: String
    let expected: Double?
    var testDescription: String { "load7Session \(target) n=\(daily.count)" }
}

struct ReadinessCategoryCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["hrvZ", "rhrZ", "sleepScore", "loadZ", "category", "composite"]
    let hrvZ, rhrZ, loadZ: Double?
    let sleepScore: Int?
    let category: String?
    let composite: Double?
    var testDescription: String { "category -> \(category ?? "nil")" }
}

struct SyntheticHistory: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["hrv", "rhr", "sleepScore", "dailyLoad", "days"]
    struct Day: Decodable, Sendable {
        let target: String
        let hrvZ, rhrZ, loadZ: Double?
        let category: String?
        let composite: Double?
    }
    let hrv, rhr, dailyLoad: [String: Double]
    let sleepScore: [String: Int]
    let days: [Day]
    var testDescription: String { "synthetic hrv n=\(hrv.count) days=\(days.count)" }
}

enum ReadinessGolden {
    static let load7 = GoldenLoader.require(Load7SessionCase.self, file: "readiness.golden", group: "load7SessionCases")
    static let category = GoldenLoader.require(ReadinessCategoryCase.self, file: "readiness.golden", group: "categoryCases")
    static let synthetic = GoldenLoader.require(SyntheticHistory.self, file: "readiness.golden", group: "syntheticHistories")
    static let constants: ReadinessConstants = {
        struct File: Decodable { let constants: ReadinessConstants }
        let url = Bundle.module.url(forResource: "readiness.golden", withExtension: "json", subdirectory: "Resources/golden")!
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url)).constants
    }()
}

@Test func readinessConstantsMatchPython() {
    let c = ReadinessGolden.constants
    #expect(c.minDays == Baseline.minDays && c.windowDays == Baseline.windowDays && c.madScale == Baseline.madScale)
    #expect(c.wHrv == ReadinessComposite.wHrv && c.wRhr == ReadinessComposite.wRhr)
    #expect(c.wSleep == ReadinessComposite.wSleep && c.wLoad == ReadinessComposite.wLoad)
    #expect(c.sleepCenter == ReadinessComposite.sleepCenter && c.sleepSpread == ReadinessComposite.sleepSpread)
    #expect(c.high == ReadinessComposite.highThreshold && c.low == ReadinessComposite.lowThreshold)
}

@Test func readinessGoldenCounts() {
    #expect(ReadinessGolden.load7.count == 26)
    #expect(ReadinessGolden.category.count == 73)
    #expect(ReadinessGolden.synthetic.count == 3)
    let categorised = ReadinessGolden.synthetic.flatMap(\.days).filter { $0.category != nil }.count
    #expect(categorised >= 20)
}

@Test func registryEntryPointsToReadinessComposite() {
    #expect(ParityRegistry.source(for: ReadinessComposite.registryKey) == .computed)
    #expect(ParityRegistry.implementation(for: ReadinessComposite.registryKey) == "JICompute.ReadinessComposite")
}

@Test(arguments: ReadinessGolden.load7)
func load7SessionMatchesPython(_ c: Load7SessionCase) throws {
    #expect(try ReadinessComposite.load7Session(target: c.target, dailyLoad: c.daily) == c.expected)
}

@Test(arguments: ReadinessGolden.category)
func readinessCategoryMatchesPython(_ c: ReadinessCategoryCase) {
    let r = ReadinessComposite.computeReadinessCategory(hrvZ: c.hrvZ, rhrZ: c.rhrZ, sleepScore: c.sleepScore, loadZ: c.loadZ)
    #expect(r.category?.rawValue == c.category)
    #expect(r.composite == c.composite)
    #expect(r.hrvZ == c.hrvZ && r.rhrZ == c.rhrZ && r.sleepScore == c.sleepScore && r.loadZ == c.loadZ)
}

@Test(arguments: ReadinessGolden.synthetic)
func readinessSyntheticDaysMatchPython(_ h: SyntheticHistory) throws {
    for d in h.days {
        let r = try ReadinessComposite.categorical(target: d.target, hrv: h.hrv, rhr: h.rhr,
                                                   sleepScore: h.sleepScore, dailyLoad: h.dailyLoad)
        #expect(r.category?.rawValue == d.category, "\(d.target)")
        #expect(r.hrvZ == d.hrvZ && r.rhrZ == d.rhrZ && r.loadZ == d.loadZ, "\(d.target)")
        #expect(r.composite == d.composite, "\(d.target)")
    }
}
