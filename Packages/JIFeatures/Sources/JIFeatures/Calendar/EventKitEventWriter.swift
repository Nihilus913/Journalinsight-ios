#if canImport(EventKit) && !os(watchOS)
import EventKit
import Foundation
import JICore

// W-B96 C-3 (B-96): the EventKit side of the calendar export. Write-only access (iOS 17+,
// Info.plist `NSCalendarsWriteOnlyAccessUsageDescription`): the app can add events to the
// user's default calendar but can never read, change or delete any event — Toby 2026-10-04
// "one-way, write-only". All-day events (Toby's default; a usual start time is Later).
@MainActor
public final class EventKitEventWriter: CalendarEventWriting {
    private let store = EKEventStore()
    private let zone: () -> TimeZone

    public init(zone: @escaping () -> TimeZone = { DayKey.zone }) { self.zone = zone }

    /// Write-only or full access counts as granted; not determined → the iOS prompt
    /// ("Add Events Only"); denied / restricted → false, never a second prompt.
    public func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .writeOnly, .fullAccess: return true
        case .notDetermined:
            return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        default: return false
        }
    }

    public func write(_ event: PlannedCalendarEvent) async throws {
        guard let day = DayKey(iso: event.date) else { throw CocoaError(.formatting) }
        let ek = EKEvent(eventStore: store)
        ek.title = event.title
        ek.notes = event.notes
        ek.url = event.url
        ek.isAllDay = event.isAllDay
        ek.startDate = day.startDate(in: zone())
        ek.endDate = day.adding(days: 1).startDate(in: zone()).addingTimeInterval(-1)
        ek.calendar = store.defaultCalendarForNewEvents
        try store.save(ek, span: .thisEvent, commit: true)
    }
}
#endif
