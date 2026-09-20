import Foundation
import Observation
import JIPersistence

/// Add/edit-entry form state (oracle: `EntrySheet.tsx`'s local state + submit handler). Owns no
/// store directly — `save()` is handed the persistence call by `JournalViewModel` so this type
/// stays trivially previewable/testable without a live `JournalStore`.
@Observable @MainActor
public final class EntrySheetViewModel: Identifiable {
    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
    public var date: String
    public var text: String
    public var durationSec: Int
    public var mood: Mood?
    public var tags: [String]
    public var tagDraft: String = ""
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    /// `nil` for a new entry; set when editing an existing one.
    public let editingId: Int64?

    public init(editing entry: Entry? = nil, today: Date = Date()) {
        self.editingId = entry?.id
        self.date = entry?.date ?? Self.isoDate(today)
        self.text = entry?.text ?? ""
        self.durationSec = entry?.durationSec ?? 0
        self.mood = entry?.mood.flatMap(Mood.init(rawValue:))
        self.tags = entry?.tags ?? []
    }

    private static func isoDate(_ d: Date) -> String { JournalCalendarZurich.isoDay(d) }

    public var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public func addTagFromDraft() {
        let name = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !tags.contains(name) else { tagDraft = ""; return }
        tags.append(name)
        tagDraft = ""
    }

    public func removeTag(_ name: String) {
        tags.removeAll { $0 == name }
    }

    /// Runs `persist`, which does the actual store write (add or update, chosen by the caller
    /// using `editingId`). Returns whether the save succeeded.
    @discardableResult
    public func save(_ persist: (NewEntry) throws -> Void) -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        let newEntry = NewEntry(date: date, text: text, durationSec: durationSec, mood: mood?.rawValue, tags: tags)
        do {
            try persist(newEntry)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Couldn't save this entry — try again."
            return false
        }
    }
}
