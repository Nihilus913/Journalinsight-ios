import Foundation
import Testing
import JICore
import JICompute
@testable import JIHealthKit

/// RG-06 / B-112: the on-device engine called `evaluate` with an empty `MorningGateDb()` /
/// `MorningGatePrevState()`, `sleepGoalH: nil` and the hard-coded weekday table. It now takes the
/// hub's rules (`OnDeviceGateRules`: plan week, yesterday's gate state, sleep goal, the user's
/// gate config — HR cap, low-HRV nights) and keeps its own gate state night to night, so the
/// engine's tier AND reason word == `evaluate` on the same inputs with the hub's rules.
@Suite struct B112RuleParityTests {
    private let today = "2026-10-05"   // a Monday
    private func day(_ offset: Int) -> String { try! CalendarMath.addDays(today, offset) }
    private func prior(_ n: Int) -> [OnDeviceNight] {
        (1...n).reversed().map { i in
            OnDeviceNight(source: .apple, date: day(-i), hrvRmssdMs: 38 + Double(i % 5), rhrBpm: 50,
                          sleepDurationSec: 7.5 * 3600, sleepScore: 80)
        }
    }
    private func tonight(_ rmssd: Double, sleepH: Double = 7.3) -> OnDeviceNight {
        OnDeviceNight(source: .apple, date: today, hrvRmssdMs: rmssd, rhrBpm: 49, sleepDurationSec: sleepH * 3600, sleepScore: 82)
    }

    /// The hub's plan week (Mon = rest) — not the hard-coded weekday table.
    private var restMondayPlan: [GateSession] {
        var week = sessionByWeekday
        week[try! CalendarMath.isoWeekday(today)] = GateSession(name: "REST day", type: .rest)
        return week
    }

    final class RulesBox: OnDeviceGateRulesProviding, @unchecked Sendable {
        var r: OnDeviceGateRules
        private(set) var recorded: [(String, MorningGateNewState)] = []
        init(_ r: OnDeviceGateRules) { self.r = r }
        func rules(day: String) -> OnDeviceGateRules { r }
        func record(day: String, state: MorningGateNewState) { recorded.append((day, state)) }
    }

    @Test func planWeekDecidesTheSessionLikeTheHub() throws {
        let rules = RulesBox(OnDeviceGateRules(plan: restMondayPlan))
        let engine = JIComputeVerdictEngine(rules: rules)
        let r = try #require(try engine.compute(OnDeviceVerdictInput(day: today, nights: prior(28) + [tonight(40)])))
        #expect(r.sessionPrescription == "REST day")
        #expect(r.verdict.hasPrefix("REST"))
        #expect(rules.recorded.map(\.0) == [today])
    }

    @Test func engineEqualsEvaluateUnderTheHubsRulesAndRecordsState() throws {
        // A low week: the 7-day mean falls under the band (the hub's HRV-low morning).
        let nights = prior(34).enumerated().map { i, n in var n = n; if i >= 28 { n.hrvRmssdMs = 18 }; return n } + [tonight(18)]
        var config = MorningGateConfig.default
        config.hrvLowNights = 2
        let boxA = RulesBox(OnDeviceGateRules(prev: MorningGatePrevState(hrvLow: true, hrvLowN: 1), config: config))
        let boxB = RulesBox(OnDeviceGateRules(config: config))
        let withState = JIComputeVerdictEngine(rules: boxA)
        let fresh = JIComputeVerdictEngine(rules: boxB)
        let a = try #require(try withState.compute(OnDeviceVerdictInput(day: today, nights: nights)))
        let b = try #require(try fresh.compute(OnDeviceVerdictInput(day: today, nights: nights)))
        // Parity: the engine == evaluate() called with the same vitals and the hub's rules.
        let direct = try JIComputeVerdictEngine.evaluateDirect(OnDeviceVerdictInput(day: today, nights: nights),
                                                               rules: OnDeviceGateRules(prev: MorningGatePrevState(hrvLow: true, hrvLowN: 1), config: config))
        #expect(a.verdict == direct.verdict)
        #expect(a.reason == (direct.conditions.first ?? direct.verdict))
        _ = b
        // The engine keeps its own gate state (the hub's morning_go_state.json write) = evaluate's.
        #expect(boxA.recorded.last?.1 == direct.newState)
        #expect(boxB.recorded.last?.0 == today)
    }

    @Test func sleepGoalReachesTheSleepRow() throws {
        let engine = JIComputeVerdictEngine(rules: RulesBox(OnDeviceGateRules(sleepGoalH: 8)))
        let r = try #require(try engine.compute(OnDeviceVerdictInput(day: today, nights: prior(28) + [tonight(40)])))
        let row = try #require(r.signals.first { $0.key == "sleep_h" })
        #expect(row.threshold == 8)
    }

    @Test func appBoxMapsThePlanWeekAndCarriesYesterdaysState() throws {
        let box = OnDeviceGateRulesBox()
        var week = Array(repeating: ScheduledSession(name: "Z2 40min", kind: .z2), count: 7)
        week[try CalendarMath.isoWeekday(today)] = ScheduledSession(name: "REST day", kind: .rest)
        box.setPlan(week)
        box.setSleepGoal(7.5)
        let engine = JIComputeVerdictEngine(rules: box)
        let t = try #require(try engine.compute(OnDeviceVerdictInput(day: today, nights: prior(28) + [tonight(40)])))
        #expect(t.sessionPrescription == "REST day")
        #expect(t.signals.first { $0.key == "sleep_h" }?.threshold == 7.5)
        // Yesterday's recorded state is today's `prev` (prev_from_state).
        box.record(day: today, state: MorningGateNewState(date: today, hrvLow: true, rhrHigh: false, rhrDate: nil, sleepLow: false, hrvLowN: 1))
        #expect(box.rules(day: day(1)).prev.hrvLowN == 1)
        #expect(OnDeviceGateRulesBox.gatePlan(Array(week.prefix(6))) == nil)
    }

    @Test func noRulesKeepsTheOldBehaviour() throws {
        let nights = prior(28) + [tonight(40)]
        let old = try #require(try JIComputeVerdictEngine().compute(OnDeviceVerdictInput(day: today, nights: nights)))
        #expect(old.sessionPrescription == (try sessionFor(today).name))
    }
}
