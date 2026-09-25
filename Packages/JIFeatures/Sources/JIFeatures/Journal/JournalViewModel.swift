import Foundation
import Observation
import JIPersistence
import JIVault

/// Screen state + CRUD orchestration for the Journal tab (oracle: `useEntries`/`useTags` +
/// `journal.tsx`'s screen-level state). Unlocks the vault on `load()` and builds a `JournalStore`
/// bound to the resulting cipher — CLAUDE.md rule 5 / the W4 card's "`VaultManager.status`
/// (locked → RN's locked copy, never an empty list)": a locked/unavailable vault surfaces
/// `.locked`, not a silently empty entry list.
@Observable @MainActor
public final class JournalViewModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded
        case locked
        case error(String)
    }

    public private(set) var state: State = .idle
    public private(set) var entries: [Entry] = []
    public private(set) var allTags: [String] = []
    public var filters = EntryFilters.empty
    public var calendarScope: JournalCalendar.Scope = .month
    public var calendarAnchor: Date
    public var presentingSheet: EntrySheetViewModel?

    private let db: AppDatabase
    private let vault: VaultManager
    private var store: JournalStore?
    private let now: () -> Date

    public init(db: AppDatabase, vault: VaultManager, now: @escaping () -> Date = Date.init) {
        self.db = db
        self.vault = vault
        self.now = now
        self.calendarAnchor = now()
    }

    /// Registry/Gallery preview (B-57 W1 fixer f3): the Journal board as it looks once loaded, with
    /// fixture entries instead of an unlocked vault — the sweep never runs `load()`, so without this
    /// the preview could only show its loading spinner. Not reachable from the app.
    init(previewEntries: [Entry], db: AppDatabase, vault: VaultManager, now: @escaping () -> Date) {
        self.db = db
        self.vault = vault
        self.now = now
        self.calendarAnchor = now()
        self.entries = previewEntries
        self.state = .loaded
    }

    public var filteredEntries: [Entry] { JournalSearch.filterEntries(entries, filters) }
    public var streak: JournalStreak.Stats { JournalStreak.computeStreak(dates: entries.map(\.date), today: now()) }
    public var entryDates: Set<String> { Set(entries.map(\.date)) }
    /// B-57 W1 board: the streak card's Mon–Sun dots and its "Today open" line.
    public var weekDots: [JournalWeekDot] { journalWeekDots(dates: entries.map(\.date), today: now()) }
    public var todayWritten: Bool { journalTodayWritten(dates: entries.map(\.date), today: now()) }
    public var today: Date { now() }

    public func load() async {
        state = .loading
        do {
            let cipher = try await vault.unlock()
            guard case .unlocked = await vault.status else {
                state = .locked
                return
            }
            let store = JournalStore(db: db, cipher: cipher)
            self.store = store
            try refresh(from: store)
            state = .loaded
        } catch {
            state = .error("Couldn't unlock your journal — try again.")
        }
    }

    private func refresh(from store: JournalStore) throws {
        entries = try store.listEntries()
        allTags = try store.allTags()
    }

    public func beginNewEntry() {
        presentingSheet = EntrySheetViewModel(today: now())
    }

    /// B-57 W1 board "Check-in · How is today landing?": a 1–5 tap opens today's new entry with
    /// that mood already picked (the entry's mood is the Journal's only mood store).
    public func beginNewEntry(moodScore: Int) {
        let sheet = EntrySheetViewModel(today: now())
        sheet.mood = journalMood(forScore: moodScore)
        presentingSheet = sheet
    }

    /// The JournalCalendar board's day card: a new entry dated the chosen day.
    public func beginNewEntry(onDay iso: String) {
        presentingSheet = EntrySheetViewModel(today: JournalCalendarZurich.date(fromISODay: iso).map { $0.addingTimeInterval(12 * 3600) } ?? now())
    }

    public func beginEditEntry(_ entry: Entry) {
        presentingSheet = EntrySheetViewModel(editing: entry, today: now())
    }

    public func saveSheet() {
        guard let sheet = presentingSheet, let store else { return }
        let saved = sheet.save { newEntry in
            if let id = sheet.editingId {
                try store.updateEntry(id: id, newEntry, now: self.now())
            } else {
                try store.addEntry(newEntry, now: self.now())
            }
        }
        guard saved else { return }
        presentingSheet = nil
        do { try refresh(from: store) } catch { state = .error("Couldn't reload your entries.") }
    }

    public func dismissSheet() {
        presentingSheet = nil
    }

    public func deleteEntry(_ entry: Entry) {
        guard let store else { return }
        do {
            try store.deleteEntry(id: entry.id)
            try refresh(from: store)
        } catch {
            state = .error("Couldn't delete this entry.")
        }
    }

    public func shiftCalendar(_ dir: Int) {
        calendarAnchor = JournalCalendar.shiftAnchor(calendarScope, anchor: calendarAnchor, dir: dir)
    }
}
