import Foundation

// W-ONDEVICE O-7: public factories so the on-device provider (`JIHealthKit`) can return the hub's
// own DTOs (the synthesized memberwise initialisers are internal to JICore). Additive only — the
// wire shape and `CodingKeys` are unchanged.

extension MorningResponse {
    public static func onDevice(
        verdict: String?, verdictDate: String?, carbWatchFloor: Double, isStale: Bool?,
        gateSignals: [GateSignal]?
    ) -> MorningResponse {
        MorningResponse(
            verdict: verdict, verdictDate: verdictDate, carbs3dAvg: nil, carbWatchFloor: carbWatchFloor,
            isStale: isStale, sessionForToday: nil, gateSignals: gateSignals, verdictOverride: nil, gateAnswer: nil
        )
    }
}

extension MorningVerdict {
    public static func onDevice(date: String, verdict: String, reason: String?, sessionPrescription: String?, computedAt: String) -> MorningVerdict {
        MorningVerdict(date: date, verdict: verdict, reason: reason, sessionPrescription: sessionPrescription, computedAt: computedAt)
    }
}
