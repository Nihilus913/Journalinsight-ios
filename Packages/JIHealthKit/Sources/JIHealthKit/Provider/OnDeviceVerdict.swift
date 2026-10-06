import Foundation
import JICompute
import JICore

/// W-ONDEVICE O-7: what the on-device compute is handed — every stored night (Apple, plus Garmin
/// only when the hub seed ran, O-8) on/before `day`, oldest first. Raw values: the compute
/// derives every baseline itself (recompute-on-read).
public struct OnDeviceVerdictInput: Sendable, Equatable {
    public var day: String
    public var nights: [OnDeviceNight]
    public init(day: String, nights: [OnDeviceNight]) { self.day = day; self.nights = nights }
}

/// The on-device verdict in the hub's own vocabulary, so `MorningVerdict` / `MorningResponse` are
/// filled exactly as `GET /planning/morning(-verdict)` fills them.
public struct OnDeviceVerdictResult: Sendable, Equatable {
    /// The hub's verdict string (`"GO — Strength A"`, `"MODIFY — …"`, `"REST — …"`).
    public var verdict: String
    public var reason: String?
    public var sessionPrescription: String?
    /// The `morning_go.gate_signals` rows behind the verdict (values shown even while calibrating).
    public var signals: [GateSignal]
    /// HRV-band baseline nights available before `day` (Apple + Garmin, `hrv_band`); < 28 =
    /// calibrating (the verdict is still shown, labelled as an estimate — Toby Q2).
    public var baselineNights: Int
    /// O-10: digest of the input nights (set by the provider, not the compute).
    public var inputsDigest: String?
    /// O-10: the night's wake (main sleep end) from HealthKit, for the wake -> verdict latency.
    public var wakeAt: Date?

    public init(verdict: String, reason: String?, sessionPrescription: String?, signals: [GateSignal], baselineNights: Int,
                inputsDigest: String? = nil, wakeAt: Date? = nil) {
        self.verdict = verdict; self.reason = reason; self.sessionPrescription = sessionPrescription
        self.signals = signals; self.baselineNights = baselineNights
        self.inputsDigest = inputsDigest; self.wakeAt = wakeAt
    }
}

extension OnDeviceVerdictInput {
    /// O-10: a stable digest of what the compute read (FNV-1a 64 over a canonical rendering), so
    /// two shadow rows with the same digest saw the same inputs.
    public var digest: String {
        func v(_ x: Double?) -> String { x.map { "\($0)" } ?? "-" }
        var text = day
        for n in nights {
            text += "|\(n.source.rawValue),\(n.date),\(v(n.hrvRmssdMs)),\(v(n.rhrBpm)),\(v(n.sleepDurationSec)),\(v(n.sleepScore))"
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return String(hash, radix: 16)
    }
}

/// The compute seam the L1 port (`HrvBand` + `mergeRecoveryDays` + `appleGateInputs` +
/// `MorningGate.evaluate`, JICompute) plugs into. Pure and synchronous: the 120-day budget is
/// < 2 s on device (O-9).
public protocol OnDeviceVerdictComputing: Sendable {
    /// `nil` = no night for `input.day` yet ("missing", never a guessed verdict).
    func compute(_ input: OnDeviceVerdictInput) throws -> OnDeviceVerdictResult?
}

/// Toby Q2 (2026-10-04): while the HRV band is calibrating, the verdict is shown with its values,
/// labelled "Estimate — calibrating (N/28 nights)".
public enum OnDeviceVerdictLabel {
    /// `hrv_band.BASELINE_NIGHTS` — the L1 `HrvBand` constant (one source).
    public static let baselineNights = HrvBand.baselineNights

    public static func isCalibrating(nights: Int) -> Bool { nights < baselineNights }

    public static func calibrating(nights: Int) -> String {
        "Estimate — calibrating (\(max(0, nights))/\(baselineNights) nights)"
    }

    /// One line for the Developer screen / banner: the label in front while calibrating.
    public static func headline(_ result: OnDeviceVerdictResult) -> String {
        isCalibrating(nights: result.baselineNights)
            ? "\(calibrating(nights: result.baselineNights)) · \(result.verdict)" : result.verdict
    }

    /// `reason` with the calibrating label in front while calibrating; unchanged otherwise.
    static func reason(_ result: OnDeviceVerdictResult) -> String? {
        guard isCalibrating(nights: result.baselineNights) else { return result.reason }
        let label = calibrating(nights: result.baselineNights)
        guard let reason = result.reason, !reason.isEmpty else { return label }
        return "\(label) · \(reason)"
    }

    /// W-FIX-P2 RG-16 (B-44od): the source word on the gate/Decide HRV row while the PHONE's
    /// baseline is calibrating — every other screen and the ntfy text use the hub's band, so the
    /// row says whose baseline it is instead of disagreeing silently.
    public static let phoneBaselineWord = "phone baseline"

    /// The gate rows the on-device overlay serves: while calibrating, the HRV row's note starts
    /// with "phone baseline" ("phone baseline · Calibrating (2/28 nights)"); unchanged otherwise.
    public static func sourceLabelled(_ result: OnDeviceVerdictResult) -> [GateSignal] {
        guard isCalibrating(nights: result.baselineNights) else { return result.signals }
        let tag = "\(phoneBaselineWord) \(max(0, result.baselineNights))/\(baselineNights)"
        return result.signals.map { signal in
            guard signal.key == "hrv" else { return signal }
            var s = signal
            s.note = s.note.map { $0.isEmpty ? tag : "\(tag) · \($0)" } ?? tag
            return s
        }
    }

    /// The HRV signal carries the label as its note while calibrating (the value stays visible).
    static func signals(_ result: OnDeviceVerdictResult) -> [GateSignal] {
        guard isCalibrating(nights: result.baselineNights) else { return result.signals }
        let label = calibrating(nights: result.baselineNights)
        return result.signals.map { signal in
            guard signal.key == "hrv" else { return signal }
            var s = signal
            s.note = s.note.map { "\(label) · \($0)" } ?? label
            return s
        }
    }
}
