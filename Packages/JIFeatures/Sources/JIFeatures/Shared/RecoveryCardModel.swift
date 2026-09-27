import JICompute
import JIDesign

/// B-57 W3 — what the recovery-score card shows (board `1 Today/03 GateRationale`). Pure.
/// A missing or calibrating score is a word ("— No data" / "— Calibrating"), never 0 or 50.
public nonisolated struct RecoveryCardModel: Equatable, Sendable {
    public let headline: String
    public let status: String?
    public let isLow: Bool
    public let drivers: [DriverBar]
    public let note: String

    public static let note = "One score from overnight HRV, resting HR and sleep (length, deep, REM), each against your normal. It shows a number once all three have \(PersonalNormal.minN) nights."

    public static func make(result: RecoveryScoreResult?, reasonWord: String?, sleepGoalH: Double) -> RecoveryCardModel {
        let order: [(RecoveryComponentKey, String)] = [(.hrv, "HRV"), (.sleep, "Sleep"), (.rhr, "Resting HR"), (.load, "Load")]
        let drivers = order.map { key, label in
            driver(key, label, result?.component(key), sleepGoalH: sleepGoalH)
        }
        guard let result else {
            return RecoveryCardModel(headline: "— \(reasonWord ?? "No data")", status: nil, isLow: false, drivers: drivers, note: note)
        }
        switch result.status {
        case .calibrating:
            return RecoveryCardModel(headline: "— Calibrating", status: nil, isLow: false, drivers: drivers, note: note)
        case .missing:
            return RecoveryCardModel(headline: "— No data", status: nil, isLow: false, drivers: drivers, note: note)
        case .ok:
            guard let score = result.score else {
                return RecoveryCardModel(headline: "— No data", status: nil, isLow: false, drivers: drivers, note: note)
            }
            let low = score < RecoveryScore.lowScore
            return RecoveryCardModel(headline: "\(score)", status: low ? "Recovery low" : "In your normal range",
                                     isLow: low, drivers: drivers, note: note)
        }
    }

    /// Words: HRV/RHR/Load follow the raw value (z is sign-flipped so higher = better; z ≤ −1 on RHR
    /// means the raw RHR is high). Sleep reads against the user's goal. Amber tint follows z ≤ −1
    /// (the bad direction); the sleep row otherwise wears the sleep metric colour. Never `.go`.
    private static func driver(_ key: RecoveryComponentKey, _ label: String, _ c: RecoveryComponent?, sleepGoalH: Double) -> DriverBar {
        guard let c else { return DriverBar(id: key.rawValue, label: label, value: nil, word: "No data") }
        let fill = c.z.map { ($0 + RecoveryScore.zCap) / (2 * RecoveryScore.zCap) }
        switch c.status {
        case .calibrating: return DriverBar(id: key.rawValue, label: label, value: nil, word: "Calibrating")
        // W-B57-W3 fixer: the rule-5 reason word, the same one GateRationale's Load row uses.
        case .noReading: return DriverBar(id: key.rawValue, label: label, value: nil, word: JIMissingReason.noData.rawValue)
        case .flat, .ok:
            let z = c.z ?? 0
            if key == .sleep {
                guard let v = c.value else { return DriverBar(id: key.rawValue, label: label, value: fill, word: "In your normal") }
                return DriverBar(id: key.rawValue, label: label, value: fill, word: v >= sleepGoalH ? "Above goal" : "Below goal",
                                 tint: z <= -1 ? .reduced : .sleep)
            }
            let higherIsWorse = key != .hrv
            let word: String
            if z <= -1 { word = higherIsWorse ? "High" : "Low" }
            else if z >= 1 { word = higherIsWorse ? "Low" : "High" }
            else { word = "In your normal" }
            return DriverBar(id: key.rawValue, label: label, value: fill, word: word, tint: z <= -1 ? .reduced : nil)
        }
    }
}
