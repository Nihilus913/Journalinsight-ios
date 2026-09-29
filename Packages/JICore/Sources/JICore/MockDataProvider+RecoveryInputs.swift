import Foundation

/// B-57 W3 — deterministic inputs so the Gallery and the sweep render a real score and bands.
/// Pure date math in UTC (no `Calendar.current`), so the same `date` always yields the same days.
extension MockDataProvider: RecoveryInputsProviding {
    public func recoveryInputs(date: String, windowDays: Int) async throws -> [RecoveryInputDay] {
        Self.recoveryInputDays(date: date, windowDays: windowDays)
    }

    /// W-FIX10 R-04: the mock's baseline is settled (its 42 days fill every normal), so the block
    /// says "ok" — the fixtures keep their real score and bands.
    public func recoveryInputsReport(date: String, windowDays: Int) async throws -> RecoveryInputsReport {
        let days = Self.recoveryInputDays(date: date, windowDays: windowDays)
        return RecoveryInputsReport(date: date, days: days, calibration: Self.recoveryCalibration(nights: min(days.count, 28)))
    }

    /// An "ok" (≥ 14 nights) or "calibrating" block for `nights` real nights, every component alike.
    public static func recoveryCalibration(nights: Int, nightsNeeded: Int = 14) -> RecoveryCalibration {
        let calibrating = nights < nightsNeeded
        let status = calibrating ? "calibrating" : "ok"
        let comps = Dictionary(uniqueKeysWithValues: ["hrv", "rhr", "sleep"].map {
            ($0, RecoveryCalibrationComponent(status: status, nights: nights))
        })
        return RecoveryCalibration(status: status, calibrating: calibrating, nights: nights,
                                   nightsNeeded: nightsNeeded, components: comps)
    }

    /// The same days, synchronously (the Gallery's seeded `RecoveryInsightService`).
    public static func recoveryInputDays(date: String, windowDays: Int) -> [RecoveryInputDay] {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        guard let end = fmt.date(from: date) else { return [] }
        return (0..<max(windowDays, 0)).reversed().map { k in
            let d = fmt.string(from: end.addingTimeInterval(Double(-k) * 86_400))
            return RecoveryInputDay(date: d, hrvMs: 40 + Double(k % 5), rhrBpm: 55 + Double(k % 3),
                                    sleepH: 7 + Double(k % 4) * 0.25, deepH: 1 + Double(k % 3) * 0.1,
                                    remH: 1.5 + Double(k % 2) * 0.2, loadMin: 30 + Double(k % 6) * 10)
        }
    }
}
