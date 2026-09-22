import Testing
import SwiftUI
import JIDesign
import JIPersistence
@testable import JIFeatures

/// B-33 L6 (W-B33 Contract): `JournalSearchView(scopes:query:)` replaces `EntrySearchBar`.
/// L4 references it by name from `Tab(role: .search)`, so the signature and the unscoped
/// default are the contract — not an implementation detail.
@Suite @MainActor struct JournalSearchViewTests {
    @Test func unscopedIsTheDefaultAndMeansNoTag() {
        var query = ""
        let view = JournalSearchView(scopes: ["training", "work"], query: Binding(get: { query }, set: { query = $0 }))
        #expect(JournalSearchView.allScope == "All")
        #expect(view.selectedTag == nil, "a fresh search is unscoped — every tag, not the first one")
    }

    @Test func theQueryBindingIsTwoWay() {
        var query = "sore legs"
        let binding = Binding(get: { query }, set: { query = $0 })
        _ = JournalSearchView(scopes: [], query: binding)
        binding.wrappedValue = "rest day"
        #expect(query == "rest day")
    }

    /// The scopes are the old tag capsules, so they may not change what a search means: an
    /// unscoped search is still every entry, a scoped one still the `EntryFilters` tag axis.
    @Test func scopeMapsOntoTheSameTagAxisAsEntryFilters() {
        let entries = [
            Entry(id: 1, date: "2026-09-20", ts: "2026-09-20T08:00:00.000Z", text: "intervals", durationSec: 60, mood: nil, tags: ["training"]),
            Entry(id: 2, date: "2026-09-21", ts: "2026-09-21T08:00:00.000Z", text: "desk day", durationSec: 60, mood: nil, tags: ["work"]),
        ]
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "", tag: nil)).count == 2)
        #expect(JournalSearch.filterEntries(entries, EntryFilters(query: "", tag: "training")).map(\.id) == [1])
    }
}
