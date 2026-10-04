import Foundation

/// W-B92 C-3 — previews and fixture screens: a month of planned days from a fixed mock week
/// (Mon S, Tue I, Wed S, Thu Z2, Fri S, Sat I, Sun rest), built with the offline builder.
extension MockDataProvider: TrainingCalendarProviding {
    static let mockCalendarWeek: [(String, String)] = [
        ("Day 1 Full Upper + Z2 40min", "strength"), ("Norwegian 4x4 intervals", "interval"),
        ("Day 2 Full Upper + Z2 60min", "strength"), ("Long Zone 2 75-90min", "z2"),
        ("Day 3 Full Upper + Z2 60min", "strength"), ("Norwegian 4x4 intervals", "interval"), ("Rest", "rest"),
    ]

    public func trainingCalendar(month: String) async throws -> TrainingCalendarMonth {
        let today = DayKey.today().iso
        guard let m = TrainingCalendarMonth.offline(month: month, today: today, planned: { _, wd in
            let (name, type) = Self.mockCalendarWeek[wd]
            return TrainingCalendarPlanned(name: name, type: type, prescription: name, source: "table")
        }) else { throw TrainingCalendarUnavailable() }
        return m
    }
}
