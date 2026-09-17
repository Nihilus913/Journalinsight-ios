import Testing
import JIPersistence
@testable import JIFeatures

private func e(_ id: Int64, _ text: String, _ mood: Mood?, _ tags: [String]) -> Entry {
    Entry(id: id, date: "2026-08-0\(id)", ts: "2026-08-0\(id)T08:00:00.000Z", text: text, durationSec: 300, mood: mood?.rawValue, tags: tags)
}

@Suite struct JournalSearchTests {
    let entries: [Entry] = [
        e(1, "Great run this morning, felt strong.", .great, ["training", "run"]),
        e(2, "Rough day at work, low energy.", .bad, ["work"]),
        e(3, "Quiet evening, read a book.", .okay, ["reading"]),
        e(4, "Another training session, legs are sore.", .good, ["training"]),
    ]

    @Test func emptyFiltersIsIdentity() {
        #expect(JournalSearch.filterEntries(entries, .empty) == entries)
    }

    @Test func hasActiveFiltersFalseUntilAnyAxisSet() {
        #expect(!JournalSearch.hasActiveFilters(.empty))
        #expect(!JournalSearch.hasActiveFilters(EntryFilters(query: "  ")))
        #expect(JournalSearch.hasActiveFilters(EntryFilters(query: "run")))
        #expect(JournalSearch.hasActiveFilters(EntryFilters(mood: .good)))
        #expect(JournalSearch.hasActiveFilters(EntryFilters(tag: "training")))
    }

    @Test func textQueryMatchesCaseInsensitivelyAgainstTextOnly() {
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "training session")).map(\.id) == [4])
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "ROUGH DAY")).map(\.id) == [2])
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "nonexistent")).isEmpty)
    }

    @Test func moodFiltersToExactMatch() {
        #expect(JournalSearch.filterEntries(entries, EntryFilters(mood: .great)).map(\.id) == [1])
        #expect(JournalSearch.filterEntries(entries, EntryFilters(mood: .good)).map(\.id) == [4])
    }

    @Test func tagFiltersToEntriesCarryingIt() {
        #expect(JournalSearch.filterEntries(entries, EntryFilters(tag: "training")).map(\.id) == [1, 4])
        #expect(JournalSearch.filterEntries(entries, EntryFilters(tag: "reading")).map(\.id) == [3])
    }

    @Test func clearingQueryRestoresFullList() {
        let narrowed = JournalSearch.filterEntries(entries, EntryFilters(query: "run"))
        #expect(narrowed.count < entries.count)
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "")) == entries)
    }

    @Test func tagAndMoodCombinationNarrows() {
        #expect(JournalSearch.filterEntries(entries, EntryFilters(mood: .good, tag: "training")).map(\.id) == [4])
    }

    @Test func tagAndMoodCombinationNoOverlapEmpty() {
        #expect(JournalSearch.filterEntries(entries, EntryFilters(mood: .bad, tag: "training")).isEmpty)
    }

    @Test func queryTagCombination() {
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "sore", tag: "training")).map(\.id) == [4])
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "run", tag: "work")).isEmpty)
    }

    @Test func queryMoodTagAllThreeTogether() {
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "legs", mood: .good, tag: "training")).map(\.id) == [4])
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "legs", mood: .bad, tag: "training")).isEmpty)
    }
}
