import Foundation
import Observation
import JIPersistence

/// Today's local-calendar date as `yyyy-MM-dd` — every Mind write is keyed off this (never
/// `Date()` alone, which would carry a time component the RN oracle's rows never have).
public nonisolated func todayISOString(now: Date = Date(), calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: now)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// Mind screen view model — entirely on-device (no hub calls this wave; oracle `app/mind.tsx`).
/// Simpler than a hub-backed screen's `SectionLoader` split: the three stores either succeed or
/// throw (a local GRDB/cipher failure), so this tracks one `Phase` over all four reads, mirroring
/// the oracle's "any isLoading tick reads as loading" convention.
@Observable @MainActor
public final class MindViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var today: CheckIn?
    public private(set) var recentCheckins: [CheckIn] = []
    public private(set) var events: [MindEvent] = []
    public private(set) var latestWho5: Who5Entry?

    private let checkins: CheckInStore
    private let eventStore: EventStore
    private let who5Store: Who5Store
    private let now: () -> Date

    public init(checkins: CheckInStore, eventStore: EventStore, who5Store: Who5Store, now: @escaping () -> Date = Date.init) {
        self.checkins = checkins
        self.eventStore = eventStore
        self.who5Store = who5Store
        self.now = now
    }

    public var checkedInToday: Bool { today != nil }
    public var snapshot: MindSnapshot { mindSnapshot(today) }
    public var who5Due: Bool { who5DueThisWeek(latestWho5?.date, now: now()) }

    public func load() async {
        phase = .loading
        await refresh()
    }

    public func refresh() async {
        do {
            today = try checkins.getByDate(todayISOString(now: now()))
            recentCheckins = try checkins.recent(7)
            events = try eventStore.recent(20)
            latestWho5 = try who5Store.latest()
            phase = .loaded
        } catch {
            phase = .error(Self.describe(error))
        }
    }

    @discardableResult
    public func upsertCheckin(_ n: NewCheckIn) async -> Bool {
        do {
            try checkins.upsertToday(n, now: now())
            await refresh()
            return true
        } catch {
            phase = .error(Self.describe(error))
            return false
        }
    }

    @discardableResult
    public func addEvent(_ n: NewMindEvent) async -> Bool {
        do {
            try eventStore.addEvent(n, now: now())
            await refresh()
            return true
        } catch {
            phase = .error(Self.describe(error))
            return false
        }
    }

    public func deleteEvent(_ id: Int64) async {
        do {
            try eventStore.deleteEvent(id)
            events.removeAll { $0.id == id }
        } catch {
            phase = .error(Self.describe(error))
        }
    }

    @discardableResult
    public func addWho5(_ n: NewWho5) async -> Bool {
        do {
            try who5Store.add(n, now: now())
            await refresh()
            return true
        } catch {
            phase = .error(Self.describe(error))
            return false
        }
    }

    private static func describe(_ error: Error) -> String {
        "Couldn't save — try again. (\(error))"
    }
}
