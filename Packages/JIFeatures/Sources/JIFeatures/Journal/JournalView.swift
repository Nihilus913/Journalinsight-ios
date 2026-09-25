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
    /// The behaviour deck's store; the registry preview passes nil so the sweep never opens the
    /// on-disk database.
    private let deckStore: BehaviorLogStore?

    public init(model: JournalViewModel) {
        self.model = model
        self.deckStore = BehaviorCardDeck.onDiskStore
    }

    init(model: JournalViewModel, deckStore: BehaviorLogStore?) {
        self.model = model
        self.deckStore = deckStore
    }

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
        .navigationSubtitle("On this phone only")   // B-57 W1 board 4/01
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
        Button { model.beginNewEntry() } label: { Image(systemName: "plus") }
            .accessibilityLabel("New entry")
            .accessibilityIdentifier("journal-new-entry")
    }

    /// B-57 W1 board 4/01, top to bottom: Streak card (with the Mon–Sun dots) · Check-in (1–5) ·
    /// Today's prompt · Entries (with the Calendar link). The behaviour deck keeps its place under
    /// the entries — the board has no slot for it, and dropping it would drop a feature.
    @ViewBuilder
    private var loadedSections: some View {
        Section {
            BoardSummaryCard(
                systemImage: "flame", title: "Streak", trailing: "This week",
                value: "\(model.streak.current)", unit: model.streak.current == 1 ? "day" : "days",
                status: model.todayWritten
                    ? BoardStatus(word: "Written today", systemImage: "checkmark", role: .go)
                    : BoardStatus(word: "Today open", systemImage: "minus", role: .reduced)
            ) {
                JournalWeekDotsRow(dots: model.weekDots)
            }
            .accessibilityIdentifier("journal-streak")
        }

        Section {
            JournalMoodCheckIn { model.beginNewEntry(moodScore: $0) }
        } header: {
            BoardSectionHeader("Check-in", caption: "10 seconds")
        }

        Section {
            JournalPromptCard(prompt: JournalPrompts.todaysPrompts(model.today).first ?? "How are you feeling?") {
                model.beginNewEntry()
            }
        } header: {
            BoardSectionHeader("Today\u{2019}s prompt")
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
            BoardSectionHeader(title: "Entries") {
                NavigationLink {
                    JournalCalendarScreen(model: model)
                } label: {
                    Text("Calendar").jiFont(.subheadline, weight: .semibold, tint: .info)
                }
                .accessibilityIdentifier("journal-calendar-link")
            }
        }

        Section {
            BehaviorCardDeck(store: deckStore)
        } header: {
            BoardSectionHeader("Behaviours")
        }
    }
}

/// The streak card's Mon–Sun row: a filled dot for a written day, a dashed ring for today while
/// it is still open, a faint ring for days to come.
struct JournalWeekDotsRow: View {
    let dots: [JournalWeekDot]
    @Environment(\.jiTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            ForEach(dots) { dot in
                VStack(spacing: 6) {
                    // W-FIX4 PF-05: at AX sizes the initial and the ring shrink to the column
                    // (one seventh of the card) instead of pushing the card past the screen.
                    Text(dot.initial).jiFont(.label, tint: .muted)
                        .lineLimit(1).minimumScaleFactor(0.4)
                    ZStack {
                        if dot.written {
                            Circle().fill(theme.color(.info))
                        } else if dot.isToday {
                            Circle().strokeBorder(theme.color(.info), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        } else {
                            Circle().strokeBorder(theme.color(.control), lineWidth: 2)
                        }
                    }
                    .frame(maxWidth: size, maxHeight: size)
                    .aspectRatio(1, contentMode: .fit)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(dot.id)
                .accessibilityValue(dot.written ? "Written" : dot.isToday ? "Today, open" : dot.isFuture ? "Still to come" : "Not written")
            }
        }
    }
}

/// Board "How is today landing?": five 1–5 buttons between "Rough" and "Great". A tap opens
/// today's entry with that mood picked.
struct JournalMoodCheckIn: View {
    let onPick: (Int) -> Void
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How is today landing?").jiFont(.subheadline, weight: .semibold, tint: .text)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 3 : 5)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...5, id: \.self) { score in
                    Button { onPick(score) } label: {
                        Text("\(score)").jiFont(.statValue, weight: .semibold, tint: .text)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.color(.control), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(score) of 5")
                    .accessibilityIdentifier("journal-checkin-\(score)")
                }
            }
            HStack {
                Text("Rough").jiFont(.footnote, tint: .muted)
                Spacer()
                Text("Great").jiFont(.footnote, tint: .muted)
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }
}

/// Board "Today's prompt": one prompt and a Write link that opens a new entry.
struct JournalPromptCard: View {
    let prompt: String
    let onWrite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt).jiFont(.subheadline, tint: .text).fixedSize(horizontal: false, vertical: true)
            Button("Write", action: onWrite)
                .buttonStyle(.plain)
                .jiFont(.subheadline, weight: .semibold, tint: .info)
                .accessibilityIdentifier("journal-prompt-write")
        }
        .padding(.vertical, 4)
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

    /// Board entry row: weekday + day number, a two-line snippet, the mood as "n/5" (or "—").
    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 0) {
                    Text(weekday).jiFont(.label, weight: .semibold, tint: .muted)
                    Text(dayNumber).jiFont(.cardTitleLarge, weight: .bold, tint: .text)
                }
                .frame(minWidth: 44)
                Text(snippet).jiFont(.footnote, tint: .muted).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(score.map(String.init) ?? "—").jiFont(.subheadline, weight: .bold, tint: score == nil ? .muted : .info)
                    Text("/5").jiFont(.footnote, tint: .muted)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive, action: onDelete)
                .accessibilityIdentifier("journal-entry-delete")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Entry \(entry.date)")
        .accessibilityValue("\(score.map { "Mood \($0) of 5" } ?? "No mood"). \(snippet)")
        .accessibilityHint("Opens this entry for editing")
        .accessibilityAddTraits(.isButton)
    }

    private var score: Int? { journalMoodScore(entry.mood) }
    private var day: Date? { JournalCalendarZurich.date(fromISODay: entry.date) }
    private var weekday: String { day.map { JournalCalendarZurich.formatter("EEE").string(from: $0).uppercased() } ?? "" }
    private var dayNumber: String { day.map { JournalCalendarZurich.formatter("d").string(from: $0) } ?? entry.date }

    private var snippet: String {
        entry.text.count > 140 ? String(entry.text.prefix(140)) + "…" : (entry.text.isEmpty ? "—" : entry.text)
    }
}
