import Foundation
import Observation
import JIPersistence

// W5b-L5 (P-export). Port of `mobile/app/export.tsx`'s state: five opt-in rows with live counts,
// nothing ticked by default, and one CSV / one JSON share action over the ticked set.
//
// The stores are read through their normal (cipher-carrying) accessors, so what lands in the file
// is PLAINTEXT — that is the point of an export, and the screen says so. A store the caller did
// not supply reads as "no rows", never a crash.

public nonisolated enum ExportFormat: String, Sendable, CaseIterable {
    case csv, json

    /// RN `shareContents(filename, …)`.
    public var filename: String { "healthtraining-export.\(rawValue)" }
}

@Observable @MainActor
public final class ExportViewModel {
    /// The on-device stores this screen serializes. All optional: a caller without a vault-backed
    /// database (or a preview) gets empty sections rather than a crash.
    public nonisolated struct Stores: Sendable {
        public var journal: JournalStore?
        public var checkins: CheckInStore?
        public var events: EventStore?
        public var who5: Who5Store?
        public var goals: GoalStore?

        public init(
            journal: JournalStore? = nil, checkins: CheckInStore? = nil, events: EventStore? = nil,
            who5: Who5Store? = nil, goals: GoalStore? = nil
        ) {
            self.journal = journal; self.checkins = checkins; self.events = events
            self.who5 = who5; self.goals = goals
        }
    }

    public private(set) var selection = noExportSelected()
    public private(set) var isLoading = true
    public private(set) var data = ExportData()
    /// RN `error` — the red card under the buttons.
    public private(set) var errorMessage: String?

    private let stores: Stores
    /// Memoized per format so re-rendering the two `ShareLink`s never re-serializes the whole
    /// database; cleared whenever the selection or the loaded rows change.
    private var payloadCache: [ExportFormat: String] = [:]

    public init(stores: Stores) { self.stores = stores }

    public var anySelected: Bool { !selection.isEmpty }

    public func count(_ type: ExportType) -> Int {
        switch type {
        case .journal: data.entries?.count ?? 0
        case .checkins: data.checkins?.count ?? 0
        case .events: data.events?.count ?? 0
        case .who5: data.who5?.count ?? 0
        case .goals: data.goals?.count ?? 0
        }
    }

    public func isSelected(_ type: ExportType) -> Bool { selection.contains(type) }

    public func toggle(_ type: ExportType) {
        selection.toggle(type)
        payloadCache.removeAll()
    }

    /// Reads every store once. A store that throws leaves that type at "no rows" and surfaces the
    /// reason, rather than taking the whole screen down (rule 5).
    public func load() {
        isLoading = true
        errorMessage = nil
        var failures: [String] = []
        func attempt<T>(_ label: String, _ body: () throws -> [T]) -> [T]? {
            do { return try body() } catch { failures.append(label); return nil }
        }
        data = ExportData(
            entries: stores.journal.flatMap { store in attempt("journal") { try store.listEntries() } },
            checkins: stores.checkins.flatMap { store in attempt("check-ins") { try store.listAll() } },
            events: stores.events.flatMap { store in attempt("events") { try store.listAll() } },
            who5: stores.who5.flatMap { store in attempt("WHO-5") { try store.listAll() } },
            goals: stores.goals.flatMap { store in attempt("goals") { try store.listGoals() } }
        )
        if !failures.isEmpty {
            errorMessage = "Couldn't read \(failures.joined(separator: ", ")) — those rows are missing from the export."
        }
        payloadCache.removeAll()
        isLoading = false
    }

    /// The exact bytes the share sheet hands over, for the ticked types only.
    public func payload(_ format: ExportFormat) -> String {
        if let cached = payloadCache[format] { return cached }
        let text = switch format {
        case .csv: combinedCSV(selection, data)
        case .json: combinedJSON(selection, data)
        }
        payloadCache[format] = text
        return text
    }
}
