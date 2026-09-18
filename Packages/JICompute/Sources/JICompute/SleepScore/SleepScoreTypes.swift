/// Plain data shapes for the sleep-debt port — mirrors the frozen dataclasses
/// in `app/vitals/sleep_debt.py` and the RN oracle's
/// `mobile/src/compute/sleepScore/types.ts`.
///
/// All three sleep source modules are pure arithmetic (no DB access), so these
/// describe plain data only: callers extract the numbers and dates before
/// calling in, exactly as the Python callers do.

/// Mirrors `app/vitals/sleep_debt.py::NightlySleep`.
///
/// `date` is an ISO `"YYYY-MM-DD"` calendar date with no time component
/// (Python's `datetime.date`, not `datetime.datetime`) — the package never
/// touches `Date`, `Calendar` or `TimeZone` (XC `CLAUDE.md` rule 8).
public nonisolated struct NightlySleep: Equatable, Sendable {
    public let date: String
    public let durationHours: Double

    public init(date: String, durationHours: Double) {
        self.date = date
        self.durationHours = durationHours
    }
}

/// Mirrors `app/vitals/sleep_debt.py::SleepDebtDay`.
public nonisolated struct SleepDebtDay: Equatable, Sendable {
    public let date: String
    public let durationHours: Double
    public let baselineHours: Double
    public let debtHours: Double
    public let nightsInWindow: Int

    public init(date: String, durationHours: Double, baselineHours: Double, debtHours: Double, nightsInWindow: Int) {
        self.date = date
        self.durationHours = durationHours
        self.baselineHours = baselineHours
        self.debtHours = debtHours
        self.nightsInWindow = nightsInWindow
    }
}

/// Errors the strict sleep parsers can raise.
public nonisolated enum SleepComputeError: Error, Equatable, Sendable {
    /// A naive local `"YYYY-MM-DDTHH:MM:SS"` onset that is not parseable.
    ///
    /// The TS oracle slices and `Number(...)`s these fields and would silently
    /// yield `NaN`; here a malformed onset is an error, never a wrong SD.
    case malformedOnsetTimestamp(String)
}
