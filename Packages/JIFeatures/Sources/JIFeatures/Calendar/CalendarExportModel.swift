import Foundation
import Observation
import JICore
import JIPersistence

// W-B96 C-2 (B-96, BP-24): Settings › Haptics & notifications › Calendar. Toby 2026-10-04: one
// way, write-only, all-day. Write-only access cannot read events back (its own included), so the
// PrefStore ledger of written keys is what keeps one event per (session, date).

/// The calendar side. App = `EventKitEventWriter`; tests = a fake.
@MainActor public protocol CalendarEventWriting: AnyObject {
    /// Asks for write-only access (the iOS prompt once; afterwards the stored answer).
    func requestAccess() async -> Bool
    func write(_ event: PlannedCalendarEvent) async throws
}

/// One "Next 7 days" preview row (rest days listed, marked "not written").
public nonisolated struct CalendarPreviewDay: Sendable, Equatable, Identifiable {
    public var date: String
    public var title: String
    public var isRest: Bool
    public var id: String { date }
}

@Observable @MainActor
public final class CalendarExportModel {
    public enum State: Equatable, Sendable {
        case off
        case writing(done: Int, total: Int)
        case synced(added: Int, at: Date)
        case denied
        case noWeek
    }

    nonisolated struct Stored: Codable, Sendable, Equatable {
        var enabled = false
        var ledger: [String] = []
    }

    public static let prefKey = "calendar.export"

    public private(set) var enabled: Bool
    public private(set) var state: State
    public private(set) var preview: [CalendarPreviewDay] = []
    /// Events JournalInsight has added so far (the ledger size, for the status line).
    public var writtenCount: Int { stored.ledger.count }

    private var stored: Stored
    private let writer: any CalendarEventWriting
    private let prefs: PrefStore
    private let weeks: @MainActor () async -> [PlanWeekOut]
    private let now: () -> Date
    private let zone: () -> TimeZone
    private var running = false

    public init(writer: any CalendarEventWriting, prefs: PrefStore, weeks: @escaping @MainActor () async -> [PlanWeekOut],
                now: @escaping () -> Date = Date.init, zone: @escaping () -> TimeZone = { DayKey.zone }) {
        self.writer = writer
        self.prefs = prefs
        self.weeks = weeks
        self.now = now
        self.zone = zone
        let s = ((try? prefs.get(Self.prefKey, as: Stored.self)) ?? nil) ?? Stored()
        self.stored = s
        self.enabled = s.enabled
        self.state = .off
    }

    private var today: DayKey { DayKey.today(now: now(), in: zone()) }

    /// Refreshes the preview only (no access prompt, no writes).
    public func load() async {
        preview = Self.previewDays(await weeks(), today: today)
    }

    /// The toggle. On → access prompt → first write; denied → snaps back off.
    public func setEnabled(_ on: Bool) async {
        guard on else {
            stored.enabled = false; enabled = false; state = .off; persist()
            return
        }
        guard await writer.requestAccess() else {
            stored.enabled = false; enabled = false; state = .denied; persist()
            return
        }
        stored.enabled = true; enabled = true; persist()
        await write()
    }

    /// Foreground / after the week loads: writes what is new when on; a no-op when off.
    public func sync() async {
        guard stored.enabled else { state = enabled ? state : .off; return }
        guard await writer.requestAccess() else {
            stored.enabled = false; enabled = false; state = .denied; persist()
            return
        }
        await write()
    }

    private func write() async {
        guard !running else { return }
        running = true
        defer { running = false }
        let served = await weeks()
        let day = today
        preview = Self.previewDays(served, today: day)
        let events = plannedCalendarEvents(weeks: served, today: day, daysAhead: calendarExportDaysAhead)
        guard !served.isEmpty, served.contains(where: { !$0.days.isEmpty }) else { state = .noWeek; return }
        let ledger = Set(stored.ledger)
        let todo = events.filter { !ledger.contains($0.key) }
        var added = 0
        state = .writing(done: 0, total: todo.count)
        for e in todo {
            do {
                try await writer.write(e)
                stored.ledger.append(e.key)
                added += 1
            } catch {
                // left out of the ledger → retried on the next sync.
            }
            state = .writing(done: added, total: todo.count)
        }
        // keep the ledger bounded: keys for dates more than 60 days back can never be written again.
        let cutoff = day.adding(days: -60).iso
        stored.ledger.removeAll { key in (key.split(separator: ".").last.map(String.init) ?? "9999") < cutoff }
        persist()
        state = .synced(added: added, at: now())
    }

    private func persist() { try? prefs.set(Self.prefKey, stored) }

    nonisolated static func previewDays(_ weeks: [PlanWeekOut], today: DayKey) -> [CalendarPreviewDay] {
        let end = today.adding(days: 7)
        var seen = Set<String>()
        return weeks.flatMap(\.days)
            .filter { d in DayKey(iso: d.date).map { $0 >= today && $0 < end } ?? false }
            .filter { seen.insert($0.date).inserted }
            .sorted { $0.date < $1.date }
            .map { d in
                CalendarPreviewDay(date: d.date, title: d.name ?? d.prescription ?? "—",
                                   isRest: d.type == "rest" || d.sessionType == "rest" || d.sessionId == nil)
            }
    }
}
