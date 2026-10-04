import Foundation
import Observation
import JICore
import JIPersistence

/// W-B92 C-5 (Bevel gap BP-1) — the Planner's Month view: a month of planned vs done.
/// The hub answers (`GET /training/calendar?month=`, HT `app/training/calendar.py`); the phone
/// keeps each served day's planned session in `PlannedSnapshotStore` (Toby Q3, the B-50 path).
/// When the hub cannot answer (404 / offline, B-52) the month is built here: planned = this
/// phone's snapshot, else the plan (`fallback`); every past owed day is `.unknown`, never missed.
/// Toby 2026-10-04: Q1 partial never counts as done; Q2 a past day is read-only.
@MainActor @Observable
public final class TrainingMonthModel {
    public private(set) var month: String
    public private(set) var data: TrainingCalendarMonth?
    /// true when `data` was built on the phone (no hub answer) — the header says so.
    public private(set) var isOffline = false
    public private(set) var isLoading = false

    @ObservationIgnored private let provider: (any TrainingCalendarProviding)?
    @ObservationIgnored private let store: PlannedSnapshotStore?
    @ObservationIgnored private let today: () -> String
    @ObservationIgnored private let fallback: (_ iso: String, _ weekday: Int) -> TrainingCalendarPlanned

    public init(provider: (any TrainingCalendarProviding)?, store: PlannedSnapshotStore?,
                today: @escaping () -> String, month: String? = nil,
                fallback: @escaping (_ iso: String, _ weekday: Int) -> TrainingCalendarPlanned) {
        self.provider = provider; self.store = store; self.today = today; self.fallback = fallback
        self.month = month ?? String(today().prefix(7))
    }

    public var todayISO: String { today() }

    /// Q2: a day before today is a record — its sheet has no Change day.
    public func isReadOnly(_ day: TrainingCalendarDay) -> Bool { day.date < today() }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let month = self.month
        if let provider, let served = try? await provider.trainingCalendar(month: month) {
            guard month == self.month else { return }
            data = served; isOffline = false
            _ = try? store?.recordMonth(served)
            return
        }
        guard month == self.month else { return }
        let range = (month + "-01", month + "-31")
        let device = (try? store?.snapshots(from: range.0, to: range.1)) ?? [:]
        let fallback = self.fallback
        data = TrainingCalendarMonth.offline(month: month, today: today()) { iso, wd in device[iso] ?? fallback(iso, wd) }
        isOffline = true
    }

    public func shift(by months: Int) async {
        month = trainingMonthShift(month, by: months)
        data = nil
        await load()
    }
}

// MARK: - pure helpers (tested in TrainingMonthModelTests)

private nonisolated let trainingMonthNames = ["January", "February", "March", "April", "May", "June", "July",
                                              "August", "September", "October", "November", "December"]
private nonisolated let trainingWeekdayLongNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

/// `yyyy-MM` moved by `months` (either direction); the input unchanged when malformed.
public nonisolated func trainingMonthShift(_ month: String, by months: Int) -> String {
    let p = month.split(separator: "-")
    guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]) else { return month }
    let idx = y * 12 + (m - 1) + months
    return String(format: "%04d-%02d", idx / 12, idx % 12 + 1)
}

/// "September 2026".
public nonisolated func trainingMonthTitle(_ month: String) -> String {
    let p = month.split(separator: "-")
    guard p.count == 2, let m = Int(p[1]), (1...12).contains(m) else { return month }
    return "\(trainingMonthNames[m - 1]) \(p[0])"
}

/// The 7-column Mon-first grid: leading nils up to day 1's weekday, trailing nils to a full week.
public nonisolated func trainingMonthGrid(_ m: TrainingCalendarMonth) -> [TrainingCalendarDay?] {
    let lead = TrainingCalendarMonth.dates(of: m.month)?.first?.weekday ?? 0
    var cells: [TrainingCalendarDay?] = Array(repeating: nil, count: lead) + m.days.map { Optional($0) }
    while cells.count % 7 != 0 { cells.append(nil) }
    return cells
}

/// Q1: "3 of 26 owed in September" — done days only; partial is in the detail line.
public nonisolated func trainingMonthHeadline(_ m: TrainingCalendarMonth) -> String {
    let s = m.summary
    let name = trainingMonthTitle(m.month).components(separatedBy: " ").first ?? m.month
    if s.owedToDate == 0 { return s.planned > 0 ? "— Nothing owed yet in \(name)" : "— No plan yet" }
    if s.done + s.partial + s.missed == 0 { return "— No data for \(name) yet" }
    return "\(s.done) of \(s.owedToDate) owed in \(name)"
}

/// "2 partial · 18 missed · 1 not synced yet · 22 planned" (zeros left out); nil when empty.
public nonisolated func trainingMonthDetail(_ m: TrainingCalendarMonth) -> String? {
    let s = m.summary
    let parts = [(s.partial, "partial"), (s.missed, "missed"), (s.unknown, "not synced yet"), (s.planned, "planned")]
        .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// "Activities synced to 29 Sep" — why later days show "?"; nil when the hub has no activity.
public nonisolated func trainingMonthSyncLine(_ m: TrainingCalendarMonth) -> String? {
    guard let iso = m.syncedThrough, let (_, mo, d) = trainingISOParts(iso) else { return nil }
    return "Activities synced to \(d) \(trainingMonthNames[mo - 1].prefix(3))"
}

/// ● done · ◐ partial · ✕ missed · ? not synced · ○ planned · – rest.
public nonisolated func trainingMonthGlyph(_ s: TrainingCalendarDay.State) -> String {
    switch s {
    case .done: "●"
    case .partial: "◐"
    case .missed: "✕"
    case .unknown: "?"
    case .planned: "○"
    case .rest: "–"
    }
}

public nonisolated func trainingMonthStateWord(_ s: TrainingCalendarDay.State) -> String {
    switch s {
    case .unknown: "not synced yet"
    default: s.rawValue
    }
}

/// VoiceOver: "Monday 21 September, Day 1 Full Upper + Z2 40min, done".
public nonisolated func trainingMonthCellLabel(_ day: TrainingCalendarDay) -> String {
    let date: String
    if let (_, mo, d) = trainingISOParts(day.date), let wd = TrainingCalendarMonth.dates(of: String(day.date.prefix(7)))?
        .first(where: { $0.iso == day.date })?.weekday {
        date = "\(trainingWeekdayLongNames[wd]) \(d) \(trainingMonthNames[mo - 1])"
    } else {
        date = day.date
    }
    let what = day.planned.isOwed ? day.planned.name : "Rest"
    return "\(date), \(what), \(trainingMonthStateWord(day.state))"
}

private nonisolated func trainingISOParts(_ iso: String) -> (Int, Int, Int)? {
    let p = iso.split(separator: "-")
    guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return nil }
    return (y, m, d)
}
