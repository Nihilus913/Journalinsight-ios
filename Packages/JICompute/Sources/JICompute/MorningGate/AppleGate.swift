import Foundation

/// W-ONDEVICE O-4 — the Apple branch of the morning gate. Port of `scripts/morning_go.py`
/// `apple_gate_inputs`, `gate_signals` (Apple rows: `_apple_signals`, `_recovery_signal`,
/// `night_context.context_signals`), golden-tested (`morning_apple.golden.json`). `evaluate` reads
/// `appleGateInputs` when `MorningVitals.apple` is set (B-65: an Apple night has its own inputs).
/// Constants are the Python ones, checked against the golden.

/// Yesterday's daytime HRV vs its same-class (dosed weekday / undosed weekend) 28-day mean.
public nonisolated struct AppleHrvDay: Hashable, Sendable {
    public var value: Double?
    public var baseline: Double?
    public var dosedProxy: Bool
    public init(value: Double?, baseline: Double?, dosedProxy: Bool) {
        self.value = value; self.baseline = baseline; self.dosedProxy = dosedProxy
    }
}

/// The Apple-only part of `fetch_overnight_apple()`'s dict. Last night's duration is
/// `MorningVitals.sleepDurationH`; the recovery score is `MorningVitals.recoveryScore`.
public nonisolated struct AppleNight: Hashable, Sendable {
    public var hrvBand: HrvBandResult
    public var prevSleepDurationH: Double?
    public var hrvDay: AppleHrvDay?
    /// W-CAL C-3: display rows only, never gated.
    public var contextRhr: Double?
    public var contextSleepScore: Double?

    public init(hrvBand: HrvBandResult, prevSleepDurationH: Double? = nil, hrvDay: AppleHrvDay? = nil,
                contextRhr: Double? = nil, contextSleepScore: Double? = nil) {
        self.hrvBand = hrvBand; self.prevSleepDurationH = prevSleepDurationH; self.hrvDay = hrvDay
        self.contextRhr = contextRhr; self.contextSleepScore = contextSleepScore
    }
}

/// One gate-signal arc (the hub's `gate_signals` row). The optional tail is present only on the
/// rows Python adds it to (hrv: calibrating / nights / band; recovery: calibrating / nights).
public nonisolated struct AppleGateSignal: Hashable, Sendable {
    public var key: String
    public var label: String
    public var value: Double?
    public var unit: String
    public var threshold: Double?
    public var direction: String
    public var scaleMin: Double
    public var scaleMax: Double
    /// "pass" | "amber" | "red" | "missing" | "context"
    public var status: String
    public var note: String
    public var calibrating: Bool?
    public var nights: Int?
    public var nightsNeeded: Int?
    public var bandLo: Int?
    public var bandHi: Int?
    public var bandMethod: String?

    public init(key: String, label: String, value: Double?, unit: String, threshold: Double?, direction: String,
                scaleMin: Double, scaleMax: Double, status: String, note: String, calibrating: Bool? = nil,
                nights: Int? = nil, nightsNeeded: Int? = nil, bandLo: Int? = nil, bandHi: Int? = nil, bandMethod: String? = nil) {
        self.key = key; self.label = label; self.value = value; self.unit = unit; self.threshold = threshold
        self.direction = direction; self.scaleMin = scaleMin; self.scaleMax = scaleMax; self.status = status
        self.note = note; self.calibrating = calibrating; self.nights = nights; self.nightsNeeded = nightsNeeded
        self.bandLo = bandLo; self.bandHi = bandHi; self.bandMethod = bandMethod
    }
}

/// Python's `"recovery" in m`: the score may be attached (possibly nil = DB error) or not at all.
public nonisolated enum RecoverySignalInput: Hashable, Sendable {
    case notAttached
    case attached(RecoveryScoreResult?)
}

public nonisolated struct AppleGateInputs: Hashable, Sendable {
    public let red: [String]
    public let amber: [String]
    public let ok: Bool
}

public nonisolated enum AppleGate {
    /// B-65: Walsh 2021 — under 7 h = short sleep; since B-57 W3 only the floor while no score.
    public static let appleMinSleepH = 7.0
    /// B-65: two consecutive nights under this = red.
    public static let appleSleepRedH = 6.0
    /// W-SSOT-1 SS-4: `GateSignalOut.band_method` for the Apple HRV band.
    public static let hrvBandMethod = "ln_rmssd_28n_mean_0.5sd"

    /// Python `format(x, "g")` (6 significant digits, trailing zeros stripped) via `formatFixed`
    /// — no printf/locale formatting in JICompute. Exponent form (|x| < 1e-4 or ≥ 1e6) is outside
    /// every value these rows carry (hours, bpm, ms, a 0–100 score) and falls back to `repr`.
    static func g(_ x: Double) -> String {
        guard x.isFinite, x != 0 else { return x == 0 ? (x.sign == .minus ? "-0" : "0") : "\(x)" }
        var e = Int(Foundation.log10(abs(x)).rounded(.down))
        var text = formatFixed(x, max(0, 5 - e))
        // Rounding may carry into a new digit (9.999996 -> "10.00000"): redo with one digit less.
        let digits = text.filter(\.isNumber).drop { $0 == "0" }
        if digits.count > 6 { e += 1; text = formatFixed(x, max(0, 5 - e)) }
        guard e >= -4 && e < 6 else { return "\(x)" }
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
    /// Python `round(x)` on a float → int (half-even).
    static func pyRound(_ x: Double) -> Int { Int(x.rounded(.toNearestOrEven)) }

    /// `apple_gate_inputs(m)` — nil when the night is not an Apple night.
    public static func appleGateInputs(_ m: MorningVitals, recoveryLowScore: Int = RecoveryScore.lowScore) -> AppleGateInputs? {
        guard let night = m.apple else { return nil }
        let b = night.hrvBand
        let dur = m.sleepDurationH, prev = night.prevSleepDurationH
        let rec = m.recoveryScore
        let recoveryLow = rec.map { $0 < recoveryLowScore } ?? false
        var red: [String] = [], amber: [String] = []
        if let dur, let prev, dur < appleSleepRedH, prev < appleSleepRedH {
            red.append("sleep under \(g(appleSleepRedH)) h two nights running (now \(pyFloatStr(dur)) h)")
        }
        if b.status != .pass { amber.append(b.note) }
        if let dur {
            if rec == nil && dur < appleMinSleepH { amber.append("only \(pyFloatStr(dur)) h sleep") }
        } else {
            amber.append("Apple sleep not synced yet")
        }
        if recoveryLow, let rec { amber.append("Recovery low (\(rec))") }
        let ok = b.status == .pass && dur != nil && !recoveryLow && (rec != nil || dur! >= appleMinSleepH)
        return AppleGateInputs(red: red, amber: amber, ok: ok)
    }

    /// `_recovery_signal(r)`.
    public static func recoverySignal(_ r: RecoveryScoreResult?, lowScore: Int = RecoveryScore.lowScore) -> AppleGateSignal {
        let st: String, note: String, val: Double?
        if r == nil || r?.status == .missing {
            st = "missing"; note = "No reading last night"; val = nil
        } else if let r, r.status == .calibrating {
            st = "missing"; val = nil
            note = r.nApple + r.nGarmin > 0
                ? "Calibrating — \(r.nApple) Apple + \(r.nGarmin) Garmin nights (\(r.nights)/\(PersonalNormal.minN))"
                : "Calibrating (\(r.nights)/\(PersonalNormal.minN) nights)"
        } else if let score = r?.score, score < lowScore {
            st = "amber"; note = "Recovery low (\(score))"; val = Double(score)
        } else {
            let score = r?.score
            st = "pass"; note = "Recovery \(score.map(String.init) ?? "None")"; val = score.map(Double.init)
        }
        return AppleGateSignal(key: "recovery", label: "Recovery score", value: val, unit: "", threshold: Double(lowScore),
                          direction: "min", scaleMin: 0, scaleMax: 100, status: st, note: note,
                          calibrating: r?.status == .calibrating, nights: r?.nights, nightsNeeded: PersonalNormal.minN)
    }

    /// `night_context.context_signals(rhr, sleep_score)` — rows only for values that exist.
    public static func contextSignals(rhr: Double?, sleepScore: Double?) -> [AppleGateSignal] {
        var out: [AppleGateSignal] = []
        if let rhr {
            out.append(AppleGateSignal(key: "rhr", label: "RHR", value: rhr, unit: "bpm", threshold: nil, direction: "max",
                                  scaleMin: 40, scaleMax: 90, status: "context", note: "RHR \(g(rhr)) bpm — context only"))
        }
        if let sleepScore {
            out.append(AppleGateSignal(key: "sleep", label: "Sleep score", value: sleepScore, unit: "", threshold: nil,
                                  direction: "min", scaleMin: 0, scaleMax: 100, status: "context",
                                  note: "sleep score \(g(sleepScore)) — context only"))
        }
        return out
    }

    /// `gate_signals(m, targets)` for an Apple night (`_apple_signals` + the recovery row);
    /// empty for a Garmin night (that branch is display-only on the hub and not ported here).
    public static func gateSignals(_ m: MorningVitals, recovery: RecoverySignalInput, sleepGoalH: Double?) -> [AppleGateSignal] {
        guard let night = m.apple else { return [] }
        let b = night.hrvBand
        let val = b.rollingLn.map { pyRound(Foundation.exp($0)) }
        let thr = b.lowerLn.map { pyRound(Foundation.exp($0)) }
        var shown: Double? = b.status != .missing ? val.map(Double.init) : nil
        if b.calibrating, let t = b.todayMs, t != 0 {
            // W-CAL C-4: a calibrating night still carries tonight's value (status stays missing).
            shown = pythonRound(t, 1)
        }
        var out = [AppleGateSignal(key: "hrv", label: "HRV (7-day)", value: shown, unit: "ms", threshold: thr.map(Double.init),
                              direction: "min", scaleMin: 0, scaleMax: 120, status: b.status.rawValue, note: b.note,
                              calibrating: b.calibrating, nights: b.nBaseline, nightsNeeded: HrvBand.baselineNights,
                              bandLo: b.lowerLn.map { pyRound(Foundation.exp($0)) },
                              bandHi: b.upperLn.map { pyRound(Foundation.exp($0)) }, bandMethod: hrvBandMethod)]
        let dur = m.sleepDurationH
        let scored = m.recoveryScore != nil
        let st: String, note: String
        if let dur {
            if scored {
                st = "context"
                if let goal = sleepGoalH {
                    note = "\(pyFloatStr(dur)) h sleep — \(dur >= goal ? "above" : "below") your \(g(goal)) h goal"
                } else {
                    note = "\(pyFloatStr(dur)) h sleep"
                }
            } else if dur < appleMinSleepH {
                st = "amber"; note = "\(pyFloatStr(dur)) h sleep — under \(g(appleMinSleepH)) h"
            } else {
                st = "pass"; note = "\(pyFloatStr(dur)) h sleep — \(g(appleMinSleepH)) h+ passes"
            }
        } else {
            st = "missing"; note = "no watch data last night"
        }
        out.append(AppleGateSignal(key: "sleep_h", label: "Sleep time", value: dur, unit: "h",
                              threshold: scored ? sleepGoalH : appleMinSleepH, direction: "min",
                              scaleMin: 0, scaleMax: 10, status: st, note: note))
        let d = night.hrvDay
        let cls = (d?.dosedProxy ?? false) ? "dosed weekdays" : "undosed weekends"
        let dayNote: String
        if let v = d?.value {
            dayNote = "daytime HRV \(g(v)) ms vs \(d?.baseline.map(g) ?? "—") (\(cls)) — context only"
        } else {
            dayNote = "no daytime readings yesterday — context only"
        }
        out.append(AppleGateSignal(key: "hrv_day", label: "Daytime HRV", value: d?.value, unit: "ms", threshold: d?.baseline,
                              direction: "min", scaleMin: 0, scaleMax: 120, status: "context", note: dayNote))
        out += contextSignals(rhr: night.contextRhr, sleepScore: night.contextSleepScore)
        if case .attached(let r) = recovery { out.append(recoverySignal(r)) }
        return out
    }
}
