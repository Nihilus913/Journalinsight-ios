import Foundation
import Testing
import JICore
import JICompute
@testable import JIHealthKit

/// RG-06 / B-112 (W-FIX-P2 l10): the on-device engine, run under the hub's rules (plan week,
/// Targets), returns the hub's tier AND reason word on the 3 shadow fixtures — the hub's
/// mornings 2026-10-03 (interval gate failed), 10-04 (rest) and 10-05 (the one row in
/// `plan.verdict_compare`: GO / GO, reason "Amber (HRV 7-day 22 ms — under band …)").
///
/// `Fixtures/rg06_shadow/rg06_shadow_fixtures.json` = the hub's own pipeline
/// (`fetch_overnight_apple` → `attach_recovery` → `evaluate`, empty db = the engine's
/// `MorningGateDb()`) over a fresh pg_dump; generator `gen_rg06.py` beside it. 10-04/10-05
/// expected == the stored `plan.morning_verdict` row verbatim; 10-03's stored reason predates
/// RG-09 (band then "calibrating 14/28"), the tier and reason word are unchanged.
@Suite struct B112ShadowFixtureParityTests {
    struct Night: Decodable { let source: String; let date: String; let hrvRmssdMs: Double?; let rhrBpm: Double?; let sleepDurationSec: Double?; let sleepScore: Double? }
    struct Case: Decodable { let day: String; let nights: [Night]; let expectedVerdict: String; let expectedReason: String; let storedHubVerdict: String?; let storedHubReason: String? }
    struct Session: Decodable { let name: String; let type: String }
    struct File: Decodable { let planWeek: [Session]; let cases: [Case] }

    static func load() throws -> File {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/rg06_shadow/rg06_shadow_fixtures.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    /// `upper(substring(verdict FROM '^[A-Za-z]+'))` — `plan.verdict_compare`'s class.
    static func tier(_ v: String) -> String { String(v.prefix { $0.isLetter }).uppercased() }
    /// The reason word: the reason's lead before its "(" / "—" detail ("Amber", "Interval gate
    /// failed", "Walks only").
    static func reasonWord(_ r: String) -> String {
        let cut = r.firstIndex { $0 == "(" || $0 == "—" } ?? r.endIndex
        return r[..<cut].trimmingCharacters(in: .whitespaces)
    }

    static func box(_ f: File) -> OnDeviceGateRulesBox {
        let b = OnDeviceGateRulesBox()
        b.setPlan(f.planWeek.map { ScheduledSession(name: $0.name, kind: ScheduledSessionKind(rawValue: $0.type) ?? .z2) })
        return b
    }

    static func input(_ c: Case) -> OnDeviceVerdictInput {
        OnDeviceVerdictInput(day: c.day, nights: c.nights.map {
            OnDeviceNight(source: $0.source == "garmin" ? .garmin : .apple, date: $0.date, hrvRmssdMs: $0.hrvRmssdMs,
                          rhrBpm: $0.rhrBpm, sleepDurationSec: $0.sleepDurationSec, sleepScore: $0.sleepScore)
        })
    }

    @Test func threeShadowFixturesOnFile() throws {
        let f = try Self.load()
        #expect(f.cases.map(\.day) == ["2026-10-03", "2026-10-04", "2026-10-05"])
        #expect(f.planWeek.count == 7)
    }

    @Test(arguments: ["2026-10-03", "2026-10-04", "2026-10-05"])
    func engineReturnsTheHubsTierAndReasonWord(_ day: String) throws {
        let f = try Self.load()
        let c = try #require(f.cases.first { $0.day == day })
        let r = try #require(try JIComputeVerdictEngine(rules: Self.box(f)).compute(Self.input(c)))
        #expect(Self.tier(r.verdict) == Self.tier(c.expectedVerdict), "\(day): \(r.verdict) vs \(c.expectedVerdict)")
        #expect(Self.reasonWord(r.reason ?? "") == Self.reasonWord(c.expectedReason), "\(day): \(r.reason) vs \(c.expectedReason)")
        // The stored hub row (plan.verdict_compare's hub side) — same tier and reason word.
        if let v = c.storedHubVerdict, let why = c.storedHubReason {
            #expect(Self.tier(r.verdict) == Self.tier(v))
            #expect(Self.reasonWord(r.reason ?? "") == Self.reasonWord(why))
        }
    }

    /// 10-04 and 10-05: the whole verdict and reason equal the hub's, byte for byte.
    @Test(arguments: ["2026-10-04", "2026-10-05"])
    func engineEqualsTheStoredHubRowVerbatim(_ day: String) throws {
        let f = try Self.load()
        let c = try #require(f.cases.first { $0.day == day })
        let r = try #require(try JIComputeVerdictEngine(rules: Self.box(f)).compute(Self.input(c)))
        #expect(r.verdict == c.storedHubVerdict)
        #expect(r.reason == c.storedHubReason)
    }

    /// The Targets sleep goal (`TargetsDocument.goal(.sleep)`) reaches the engine's sleep row,
    /// read at compute time — a later Targets edit is picked up without re-installing the box.
    @Test func targetsSleepGoalReachesTheSleepRow() throws {
        let f = try Self.load()
        let c = try #require(f.cases.last)
        let b = Self.box(f)
        let doc = LockedDoc(TargetsDocument(goals: TargetGoals(sleepH: 7.5)))
        b.setTargetsSource { doc.value }
        let engine = JIComputeVerdictEngine(rules: b)
        #expect(try #require(try engine.compute(Self.input(c))).signals.first { $0.key == "sleep_h" }?.threshold == 7.5)
        doc.value = TargetsDocument(goals: TargetGoals(sleepH: 8))
        #expect(try #require(try engine.compute(Self.input(c))).signals.first { $0.key == "sleep_h" }?.threshold == 8)
        doc.value = .empty   // no goal typed → no threshold (never a stand-in)
        #expect(try #require(try engine.compute(Self.input(c))).signals.first { $0.key == "sleep_h" }?.threshold == nil)
    }

    final class LockedDoc: @unchecked Sendable {
        private let lock = NSLock(); private var v: TargetsDocument
        init(_ v: TargetsDocument) { self.v = v }
        var value: TargetsDocument { get { lock.withLock { v } } set { lock.withLock { v = newValue } } }
    }
}
