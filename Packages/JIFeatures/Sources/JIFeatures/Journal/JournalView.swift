import SwiftUI
import JIDesign
import JIPersistence

/// Journal tab (oracle: `app/(tabs)/journal.tsx`). B-33 §2b.2: the screen is one inset-grouped
/// `List` — streak/prompts/deck/insights are its first sections, the calendar and the entry rows
/// compose side by side in regular width (§8.1), and each entry is a 44-pt `JIRow` with a
/// destructive swipe action. Free-text + tag search moved to the search-role tab (§2b.4,
/// `JournalSearchView`), so no filter bar renders here any more.
/// CLAUDE.md rule 5: locked/loading/error states render their own copy, never a bare empty list.
public struct JournalView: View {
    @Bindable var model: JournalViewModel

    public init(model: JournalViewModel) { self.model = model }

    public var body: some View {
        List {
            switch model.state {
            case .idle, .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .locked:
                Section { ContentUnavailableView("Journal locked", systemImage: "lock.fill") }
            case .error(let message):
                Section { ContentUnavailableView(message, systemImage: "exclamationmark.triangle") }
            case .loaded:
                loadedSections
            }
            Section { Disclaimer() }
        }
        .jiNativeFormChrome()
        // B-46 item 5: `readableColumn()` puts a hard `frame(maxWidth: 720)` on whatever it wraps.
        // On a `ScrollView`'s inner `VStack` (every other screen) that is a readable-width cap; on
        // a `List` it OVERRIDES the list's own width, so at 393 pt the list laid out 720 pt wide
        // and its rows were clipped away — exactly the "floating card on black, title + subtitle,
        // no rows" Toby saw. A `List` already handles readable width per platform (§8.2); it does
        // not need, and must not get, a fixed frame.

        .jiTheme(.native)
        .navigationTitle("Journal")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { newEntryButton }
            #else
            ToolbarItem { newEntryButton }
            #endif
        }
        .task { if model.state == .idle { await model.load() } }
        .sheet(item: $model.presentingSheet) { sheet in
            EntrySheet(model: sheet, onSave: { model.saveSheet() }, onCancel: { model.dismissSheet() })
                .jiNativeSheetSizing()
        }
    }

    private var newEntryButton: some View {
        Button { model.beginNewEntry() } label: { Image(systemName: "square.and.pencil") }
            .accessibilityLabel("New entry")
            .accessibilityIdentifier("journal-new-entry")
    }

    /// B-46 item 9: real Health-style sections — a named header over plain rows — instead of the
    /// RN-era stack of unlabelled rounded cards the L6 migration carried over verbatim.
    @ViewBuilder
    private var loadedSections: some View {
        Section { StreakHeader(stats: model.streak) } header: { Text("Streak") }
        Section { PromptsCard() } header: { Text("Today's prompts") }
        Section { BehaviorCardDeck(store: BehaviorCardDeck.onDiskStore) } header: { Text("Check-in") }
        // §8.1: the calendar composes beside the insights card in regular width and stacks in
        // compact — one layout tree, no second design. The entry rows stay real `List` rows
        // underneath (§2b.2) so the system gives them separators and swipe actions.
        Section {
            AdaptiveHStack {
                CalendarView(
                    scope: model.calendarScope, anchor: model.calendarAnchor, entryDates: model.entryDates,
                    onSelectDay: { _ in }, onShift: { model.shiftCalendar($0) }
                )
                InsightsCard(entries: model.entries)
            }
        } header: {
            Text("This month")
        }

        Section {
            if model.filteredEntries.isEmpty {
                EmptyEntriesRow(hasFilters: JournalSearch.hasActiveFilters(model.filters))
            } else {
                ForEach(model.filteredEntries.prefix(10)) { entry in
                    EntryRow(entry: entry, onOpen: { model.beginEditEntry(entry) }, onDelete: { model.deleteEntry(entry) })
                }
            }
        } header: {
            Text("Entries")
        }
    }
}

private struct EmptyEntriesRow: View {
    let hasFilters: Bool
    @Environment(\.jiTheme) private var theme
    var body: some View {
        Text(hasFilters ? "No entries match your filters" : "No entries yet")
            .jiFont(.footnote).foregroundStyle(theme.color(.muted))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EntryRow: View {
    let entry: Entry
    let onOpen: () -> Void
    let onDelete: () -> Void
    @Environment(\.jiTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            JIRow(title: entry.date, subtitle: snippet) {
                HStack(spacing: 6) {
                    Text(entry.mood.flatMap(Mood.init(rawValue:)).map(moodEmoji) ?? "—").jiFont(.emoji)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive, action: onDelete)
                .accessibilityIdentifier("journal-entry-delete")
        }
        .accessibilityLabel("Entry \(entry.date)")
        .accessibilityValue(snippet)
        .accessibilityHint("Opens this entry for editing")
    }

    private var snippet: String {
        entry.text.count > 140 ? String(entry.text.prefix(140)) + "…" : (entry.text.isEmpty ? "—" : entry.text)
    }
}
