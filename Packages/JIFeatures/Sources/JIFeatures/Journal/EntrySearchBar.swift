import SwiftUI
import JIDesign
import JIPersistence

/// Free-text/mood/tag filter bar (oracle: `EntrySearchBar.tsx`), driving `EntryFilters` via
/// `JournalSearch`.
public struct EntrySearchBar: View {
    @Binding var filters: EntryFilters
    let availableTags: [String]
    public init(filters: Binding<EntryFilters>, availableTags: [String]) {
        self._filters = filters
        self.availableTags = availableTags
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search entries", text: $filters.query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search journal entries")
                .accessibilityIdentifier("journal-search-field")

            if !availableTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button {
                                filters.tag = (filters.tag == tag) ? nil : tag
                            } label: {
                                Text(tag)
                                    .jiFont(.label)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(filters.tag == tag ? JIColor.info.opacity(0.3) : JIColor.surface2)
                                    )
                                    .foregroundStyle(JIColor.text)
                            }
                            .buttonStyle(.pressableScale)
                            .accessibilityLabel("Filter by tag \(tag)")
                            .accessibilityAddTraits(filters.tag == tag ? .isSelected : [])
                        }
                    }
                }
            }

            if JournalSearch.hasActiveFilters(filters) {
                Button("Clear filters") { filters = .empty }
                    .jiFont(.label)
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Clear filters")
            }
        }
    }
}
