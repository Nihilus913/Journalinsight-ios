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
    public init() {}

    public func compute(_ input: OnDeviceVerdictInput) throws -> OnDeviceVerdictResult? {
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
        let result = try evaluate(today: day, vitals: vitals, db: MorningGateDb(), state: MorningGatePrevState())
        let signals = AppleGate.gateSignals(vitals, recovery: .attached(recovery), sleepGoalH: nil).map(Self.dto)
        return OnDeviceVerdictResult(
            verdict: result.verdict,
            reason: result.conditions.first ?? result.verdict,
            sessionPrescription: try sessionFor(day).name,
            signals: signals,
            baselineNights: band.nBaseline
        )
    }

    /// JICompute's `gate_signals` row -> the hub's wire DTO.
    static func dto(_ s: AppleGateSignal) -> GateSignal {
        GateSignal(key: s.key, label: s.label, value: s.value, unit: s.unit, threshold: s.threshold,
                   direction: GateSignalDirection(rawValue: s.direction) ?? .min,
                   status: GateSignalStatus(rawValue: s.status) ?? .missing, note: s.note,
                   bandLo: s.bandLo.map(Double.init), bandHi: s.bandHi.map(Double.init), bandMethod: s.bandMethod)
    }
}
