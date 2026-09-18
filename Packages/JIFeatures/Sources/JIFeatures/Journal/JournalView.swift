import SwiftUI
import JIDesign
import JIPersistence

/// Journal tab (oracle: `app/(tabs)/journal.tsx`). Renders the streak header, today's prompts,
/// insights, calendar, search bar, entry list, and the persistent crisis-line disclaimer.
/// CLAUDE.md rule 5: locked/loading/error states render their own copy, never a bare empty list.
public struct JournalView: View {
    @Bindable var model: JournalViewModel

    public init(model: JournalViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch model.state {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .locked:
                    ContentUnavailableView("Journal locked", systemImage: "lock.fill")
                case .error(let message):
                    ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
                case .loaded:
                    loadedContent
                }
                Disclaimer()
            }
            .padding(16)
        }
        .navigationTitle("Journal")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.beginNewEntry() } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New entry")
                    .accessibilityIdentifier("journal-new-entry")
            }
            #else
            ToolbarItem {
                Button { model.beginNewEntry() } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New entry")
                    .accessibilityIdentifier("journal-new-entry")
            }
            #endif
        }
        .task { if model.state == .idle { await model.load() } }
        .sheet(item: $model.presentingSheet) { sheet in
            EntrySheet(model: sheet, onSave: { model.saveSheet() }, onCancel: { model.dismissSheet() })
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        StreakHeader(stats: model.streak)
        PromptsCard()
        BehaviorCardDeck()
        InsightsCard(entries: model.entries)
        CalendarView(
            scope: model.calendarScope, anchor: model.calendarAnchor, entryDates: model.entryDates,
            onSelectDay: { _ in }, onShift: { model.shiftCalendar($0) }
        )
        EntrySearchBar(filters: $model.filters, availableTags: model.allTags)

        if model.filteredEntries.isEmpty {
            Text(JournalSearch.hasActiveFilters(model.filters) ? "No entries match your filters" : "No entries yet")
                .jiFont(.footnote).foregroundStyle(JIColor.muted)
        } else {
            VStack(spacing: 0) {
                ForEach(model.filteredEntries.prefix(10)) { entry in
                    EntryRow(entry: entry, onOpen: { model.beginEditEntry(entry) })
                    Divider().opacity(0.2)
                }
            }
        }
    }
}

private struct EntryRow: View {
    let entry: Entry
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Text(entry.mood.flatMap(Mood.init(rawValue:)).map(moodEmoji) ?? "—").jiFont(.emoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date).jiFont(.bodySmall, weight: .semibold).foregroundStyle(JIColor.text)
                    Text(snippet).jiFont(.bodySmall).foregroundStyle(JIColor.muted).lineLimit(2)
                }
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Entry \(entry.date)")
        .accessibilityValue(snippet)
        .accessibilityHint("Opens this entry for editing")
    }

    private var snippet: String {
        entry.text.count > 140 ? String(entry.text.prefix(140)) + "…" : (entry.text.isEmpty ? "—" : entry.text)
    }
}
