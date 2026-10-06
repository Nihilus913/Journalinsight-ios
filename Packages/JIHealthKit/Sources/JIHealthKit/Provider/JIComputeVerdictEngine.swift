import Foundation
import JICore
import JICompute

/// W-ONDEVICE (verifier integration): the L1 JICompute port behind the L2 `OnDeviceVerdictComputing`
/// seam. Mirrors `morning_go.py` for an Apple night: `fetch_overnight_apple` (hrv_band with Garmin
/// nights completing the baseline, sleep hours rounded to 0.1) + `attach_recovery`
/// (`merge_recovery_days` -> `recovery_score`) -> `evaluate` -> `gate_signals`; `reason` =
/// `conditions[0]` (else the verdict), `session_prescription` = the plan weekday's session.
/// Pure and synchronous (O-9 budget < 2 s for 120 days x 2 sources).
public struct JIComputeVerdictEngine: OnDeviceVerdictComputing {
    /// RG-06 / B-112: the hub's gate rules (nil = the pre-RG-06 defaults: no plan week, no
    /// yesterday state, no sleep goal, default config).
    public let rules: (any OnDeviceGateRulesProviding)?

    public init(rules: (any OnDeviceGateRulesProviding)? = nil) { self.rules = rules }

    public func compute(_ input: OnDeviceVerdictInput) throws -> OnDeviceVerdictResult? {
        let r = rules?.rules(day: input.day) ?? OnDeviceGateRules()
        guard let (vitals, recovery, band) = try Self.vitals(input) else { return nil }
        let result = try evaluate(today: input.day, vitals: vitals, db: r.db, state: r.prev, config: r.config, plan: r.plan)
        rules?.record(day: input.day, state: result.newState)
        let signals = AppleGate.gateSignals(vitals, recovery: .attached(recovery), sleepGoalH: r.sleepGoalH).map(Self.dto)
        return OnDeviceVerdictResult(
            verdict: result.verdict,
            reason: result.conditions.first ?? result.verdict,
            sessionPrescription: try sessionFor(input.day, plan: r.plan).name,
            signals: signals,
            baselineNights: band.nBaseline
        )
    }

    /// `evaluate` on the engine's vitals with `rules` (parity checks, RG-06).
    public static func evaluateDirect(_ input: OnDeviceVerdictInput, rules r: OnDeviceGateRules) throws -> EvaluateResult {
        guard let (vitals, _, _) = try vitals(input) else { throw OnDeviceGateRulesError.noNight }
        return try evaluate(today: input.day, vitals: vitals, db: r.db, state: r.prev, config: r.config, plan: r.plan)
    }

    static func vitals(_ input: OnDeviceVerdictInput) throws -> (MorningVitals, RecoveryScoreResult, HrvBandResult)? {
        let day = input.day
        let nights = input.nights.filter { $0.date <= day }
        let apple = nights.filter { $0.source == .apple }
        let garmin = nights.filter { $0.source == .garmin }

        func byDate(_ rows: [OnDeviceNight], _ value: (OnDeviceNight) -> Double?) -> [String: Double] {
            var out: [String: Double] = [:]
            for n in rows { if let v = value(n) { out[n.date] = v } }   // a later duplicate wins
            return out
        }
        let appleHrv = byDate(apple, \.hrvRmssdMs)
        let appleSleep = byDate(apple, \.sleepDurationSec)
        // `fetch_overnight_apple` returns None without an Apple night for the day -> "missing".
        let dur = appleSleep[day].flatMap { $0 > 0 ? $0 : nil }
        guard appleHrv[day] != nil || dur != nil else { return nil }

        let garminHrv = byDate(garmin, \.hrvRmssdMs)
        let band = try HrvBand.compute(apple: appleHrv, today: day, garmin: garminHrv.isEmpty ? nil : garminHrv)

        func series(_ rows: [OnDeviceNight]) -> [RecoverySeriesDay] {
            rows.map { RecoverySeriesDay(date: $0.date, hrvMs: $0.hrvRmssdMs, rhrBpm: $0.rhrBpm,
                                         sleepH: $0.sleepDurationSec.map { $0 / 3600 }) }
        }
        let recovery = try RecoveryScore.compute(apple: series(apple), garmin: series(garmin), today: day)

        let prevKey = try CalendarMath.addDays(day, -1)
        let prev = appleSleep[prevKey].flatMap { $0 > 0 ? $0 : nil }
        let todayApple = apple.last { $0.date == day }
        let night = AppleNight(hrvBand: band, prevSleepDurationH: prev.map { pythonRound($0 / 3600, 1) },
                               contextRhr: todayApple?.rhrBpm, contextSleepScore: todayApple?.sleepScore)
        let vitals = MorningVitals(sleepDurationH: dur.map { pythonRound($0 / 3600, 1) },
                                   recoveryScore: recovery.score, apple: night)
        return (vitals, recovery, band)
    }

    /// JICompute's `gate_signals` row -> the hub's wire DTO.
    static func dto(_ s: AppleGateSignal) -> GateSignal {
        GateSignal(key: s.key, label: s.label, value: s.value, unit: s.unit, threshold: s.threshold,
                   direction: GateSignalDirection(rawValue: s.direction) ?? .min,
                   status: GateSignalStatus(rawValue: s.status) ?? .missing, note: s.note,
                   bandLo: s.bandLo.map(Double.init), bandHi: s.bandHi.map(Double.init), bandMethod: s.bandMethod)
    }
}

/// RG-06 / B-112: the hub's rules the on-device `evaluate` runs under — the same arguments
/// `morning_go.main()` passes (`plan_weekdays`, `prev_from_state`, the user's gate settings, the
/// Targets sleep goal).
public struct OnDeviceGateRules: Sendable {
    /// The plan's week, Monday = 0 (`sessionFor(_:plan:)`); nil = the fallback weekday table.
    public var plan: [GateSession]?
    /// Yesterday's gate flags (`prev_from_state`): drives the consecutive-low-HRV / RHR rules.
    public var prev: MorningGatePrevState
    /// Targets sleep goal (the "Sleep time" row's threshold); nil = calibrating floor.
    public var sleepGoalH: Double?
    /// The user's gate settings (`hr_cap_bpm`, `hrv_low_nights`, …).
    public var config: MorningGateConfig
    public var db: MorningGateDb

    public init(plan: [GateSession]? = nil, prev: MorningGatePrevState = MorningGatePrevState(), sleepGoalH: Double? = nil,
                config: MorningGateConfig = .default, db: MorningGateDb = MorningGateDb()) {
        self.plan = plan; self.prev = prev; self.sleepGoalH = sleepGoalH; self.config = config; self.db = db
    }
}

/// Supplies the rules for a day and keeps the engine's own gate state night to night
/// (`record` = `morning_go_state.json`'s write).
public protocol OnDeviceGateRulesProviding: Sendable {
    func rules(day: String) -> OnDeviceGateRules
    func record(day: String, state: MorningGateNewState)
}

public enum OnDeviceGateRulesError: Error { case noNight }

/// RG-06: the App's rules holder — the plan week (from the hub's plan sessions, the same
/// `plan_from_rows` rule), the sleep goal, and yesterday's gate state (the engine's own last
/// `newState`, `prev_from_state`). Lock-protected; filled before each compute.
public final class OnDeviceGateRulesBox: OnDeviceGateRulesProviding, @unchecked Sendable {
    // @unchecked: every field is read/written under `lock`.
    private let lock = NSLock()
    private var plan: [GateSession]?
    private var sleepGoalH: Double?
    /// RG-06 (W-FIX-P2 l10): the Targets document, read at each compute (`goal(.sleep)`) — the
    /// same document `morning_go.main()` passes as `targets`; wins over `setSleepGoal`.
    private var targets: (@Sendable () -> TargetsDocument?)?
    private var config: MorningGateConfig = .default
    private var lastState: MorningGateNewState?

    public init() {}

    public func setPlan(_ week: [ScheduledSession]?) { lock.withLock { plan = Self.gatePlan(week) } }
    public func setSleepGoal(_ hours: Double?) { lock.withLock { sleepGoalH = hours } }
    public func setTargetsSource(_ source: @escaping @Sendable () -> TargetsDocument?) { lock.withLock { targets = source } }

    /// The fallback weekday table in the resolver's vocabulary (session names for plan rows).
    public static let fixedWeek: [ScheduledSession] = sessionByWeekday.map {
        ScheduledSession(name: $0.name, kind: ScheduledSessionKind(rawValue: $0.type.rawValue) ?? .z2)
    }

    /// `ScheduledSession` (JICore, the plan resolver's week) -> `GateSession` (JICompute).
    public static func gatePlan(_ week: [ScheduledSession]?) -> [GateSession]? {
        guard let week, week.count == 7 else { return nil }
        return week.map { GateSession(name: $0.name, type: SessionType(rawValue: $0.kind.rawValue)) }
    }

    public func rules(day: String) -> OnDeviceGateRules {
        let source = lock.withLock { targets }
        let doc = source?()   // outside the lock: the source may read a store
        return lock.withLock {
            let state = lastState.map {
                MorningGateState(date: $0.date, hrvLow: $0.hrvLow, rhrHigh: $0.rhrHigh, rhrDate: $0.rhrDate, sleepLow: $0.sleepLow, hrvLowN: $0.hrvLowN)
            }
            let prev = (state.flatMap { try? prevFromState($0, today: day) }) ?? MorningGatePrevState()
            let goal = source != nil ? doc?.goal(.sleep) : sleepGoalH
            return OnDeviceGateRules(plan: plan, prev: prev, sleepGoalH: goal, config: config)
        }
    }

    public func record(day: String, state: MorningGateNewState) {
        lock.withLock { if day >= (lastState?.date ?? "") { lastState = state } }
    }
}
