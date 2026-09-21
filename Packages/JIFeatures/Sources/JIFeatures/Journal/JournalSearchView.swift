import SwiftUI
import JIDesign

/// B-33 §2b.4 — Journal search as the iOS 27 search-role tab. Replaces `EntrySearchBar`: the
/// free-text field is the system `.searchable` field of the enclosing `NavigationStack`, and the
/// tag capsules that used to sit under it become **search scopes** (`.searchScopes`).
///
/// Contract (W-B33): `JournalSearchView(scopes:query:)` — `scopes` are the journal's tags (the
/// caller passes `model.allTags`), `query` is the two-way free-text binding. Scope selection is
/// this view's own state; "All" is the unscoped default.
public struct JournalSearchView: View {
    public static let allScope = "All"

    let scopes: [String]
    @Binding var query: String
    @State private var scope: String = JournalSearchView.allScope
    @Environment(\.jiTheme) private var theme

    public init(scopes: [String], query: Binding<String>) {
        self.scopes = scopes
        self._query = query
    }

    /// The tag the current scope selects, or `nil` for the unscoped "All".
    public var selectedTag: String? { scope == Self.allScope ? nil : scope }

    public var body: some View {
        List {
            Section {
                JIRow(title: "Search term", systemImage: "magnifyingglass") {
                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Any" : query)
                }
                JIRow(title: "Tag", systemImage: "tag") {
                    Text(selectedTag ?? Self.allScope)
                }
            } header: {
                Text("Filters")
            } footer: {
                Text("Pick a tag scope above the results, or type to search entry text.")
            }

            if !query.isEmpty || selectedTag != nil {
                Section {
                    Button("Clear filters", role: .destructive) {
                        query = ""
                        scope = Self.allScope
                    }
                    .accessibilityIdentifier("journal-search-clear")
                }
            }
        }
        .jiNativeFormChrome()
        .jiTheme(.native)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search entries")
        .searchScopes($scope) {
            ForEach([Self.allScope] + scopes, id: \.self) { tag in
                Text(tag).tag(tag)
            }
        }
        .accessibilityIdentifier("journal-search")
    }
}
