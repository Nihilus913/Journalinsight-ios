import Foundation
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

    public init(verdict: String, reason: String?, sessionPrescription: String?, signals: [GateSignal], baselineNights: Int) {
        self.verdict = verdict; self.reason = reason; self.sessionPrescription = sessionPrescription
        self.signals = signals; self.baselineNights = baselineNights
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
    /// `hrv_band.BASELINE_NIGHTS`. Verifier: point at the L1 `HrvBand` constant once merged.
    public static let baselineNights = 28

    public static func isCalibrating(nights: Int) -> Bool { nights < baselineNights }

    public static func calibrating(nights: Int) -> String {
        "Estimate — calibrating (\(max(0, nights))/\(baselineNights) nights)"
    }

    /// `reason` with the calibrating label in front while calibrating; unchanged otherwise.
    static func reason(_ result: OnDeviceVerdictResult) -> String? {
        guard isCalibrating(nights: result.baselineNights) else { return result.reason }
        let label = calibrating(nights: result.baselineNights)
        guard let reason = result.reason, !reason.isEmpty else { return label }
        return "\(label) · \(reason)"
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
