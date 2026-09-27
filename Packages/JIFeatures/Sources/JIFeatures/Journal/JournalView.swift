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

    @State private var showCalendar = false
    @Environment(\.jiTheme) private var theme

    public var body: some View {
        // W-GUI J1 (mockup 09): the List became cards on the ground — streak card, two tiles,
        // the tinted prompt card with tag chips and ONE primary (Write), the entries card, the
        // behaviour deck, the disclaimer. Search stays in the search-role tab (B-46 item 11).
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                switch model.state {
                case .idle, .loading:
                    Surface { ProgressView().frame(maxWidth: .infinity) }
                case .locked:
                    Surface { ContentUnavailableView("Journal locked", systemImage: "lock.fill") }
                case .error(let message):
                    Surface { ContentUnavailableView(message, systemImage: "exclamationmark.triangle") }
                case .loaded:
                    loadedSections
                }
                Disclaimer().padding(.top, JISpacing.s6)
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiTheme(.native)
        .navigationTitle("Journal")
        .navigationSubtitle("Think · find · write")   // W-GUI J1 (mockup 09)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { newEntryButton }
            #else
            ToolbarItem { newEntryButton }
            #endif
        }
        .navigationDestination(isPresented: $showCalendar) { JournalCalendarScreen(model: model) }
        .task { if model.state == .idle { await model.load() } }
        .sheet(item: $model.presentingSheet) { sheet in
            EntrySheet(model: sheet, onSave: { model.saveSheet() }, onCancel: { model.dismissSheet() })
                .jiNativeSheetSizing()
                .jiSheetGround()
        }
    }

    private var newEntryButton: some View {
        JIGlassButton("plus", label: "New entry") { model.beginNewEntry() }
            .accessibilityIdentifier("journal-new-entry")
    }

    /// The mood of today's entry, when one exists (the streak card's Mood tile).
    private var todayMoodScore: Int? {
        let today = JournalCalendarZurich.isoDay(model.today)
        return model.filteredEntries.first { $0.date == today }.flatMap { journalMoodScore($0.mood) }
    }

    /// W-GUI J1 (mockup 09), top to bottom: Streak card (+ Mon–Sun dots, mood / WHO-5 tiles) ·
    /// Check-in (1–5) · This morning · prompt (tinted, chips, Write) · Recent entries (+ calendar
    /// glass button) · Behaviours.
    @ViewBuilder
    private var loadedSections: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: JISpacing.s3) {
                BoardSummaryCard(
                    systemImage: "flame", title: "Streak", trailing: "This week",
                    value: "\(model.streak.current)", unit: model.streak.current == 1 ? "day in a row" : "days in a row",
                    valueTint: .text,
                    status: model.todayWritten
                        ? BoardStatus(word: "Written today", systemImage: "checkmark", role: .go)
                        : BoardStatus(word: "Today open", systemImage: "minus", role: .reduced)
                ) {
                    JournalWeekDotsRow(dots: model.weekDots)
                }
                Text(journalStreakCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                HStack(spacing: JISpacing.tileGap) {
                    JITile(family: .factTile) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mood").jiFont(.caption).foregroundStyle(theme.color(.muted))
                            Text(journalMoodTileText(score: todayMoodScore)).jiFont(.subheadline, weight: .semibold)
                                .foregroundStyle(theme.color(todayMoodScore == nil ? .muted : .text))
                        }
                    }
                    JITile(family: .factTile) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WHO-5").jiFont(.caption).foregroundStyle(theme.color(.muted))
                            Text("— on Mind").jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.muted))
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("journal-streak")

        JISectionHeader("Check-in · 10 seconds")
        Surface(level: 1, padding: JISpacing.cardPadding) {
            JournalMoodCheckIn { model.beginNewEntry(moodScore: $0) }
        }

        JISectionHeader("This morning · prompt")
        Surface(level: 1, padding: JISpacing.cardPadding, tint: theme.color(.go)) {
            JournalPromptCard(prompt: JournalPrompts.todaysPrompts(model.today).first ?? "How are you feeling?") {
                model.beginNewEntry()
            }
        }

        HStack(alignment: .center) {
            JISectionHeader("Recent")
            Spacer(minLength: JISpacing.s2)
            JIGlassButton("calendar", label: "Calendar") { showCalendar = true }
                .padding(.trailing, JISpacing.s1)
                .accessibilityIdentifier("journal-calendar-link")
        }
        Surface(level: 1, padding: 0) {
            VStack(spacing: 0) {
                if model.filteredEntries.isEmpty {
                    EmptyEntriesRow(hasFilters: JournalSearch.hasActiveFilters(model.filters)).padding(.vertical, JISpacing.s3)
                } else {
                    let entries = Array(model.filteredEntries.prefix(10))
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { JIRowDivider().padding(.leading, 0) }
                        EntryRow(entry: entry, onOpen: { model.beginEditEntry(entry) }, onDelete: { model.deleteEntry(entry) })
                    }
                }
            }
            .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
        }

        JISectionHeader("Behaviours")
        Surface(level: 1, padding: JISpacing.cardPadding) {
            BehaviorCardDeck(store: deckStore)
        }
        Text(journalLocalCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s4)
    }
}

// MARK: - W-GUI J1 (mockup 09) copy, pure

public nonisolated let journalStreakCaption = "Missing a day does not reset anything"
public nonisolated let journalLocalCaption = "Journal and Mind live on the device. Tags like the ones above are what the coach can later correlate with HRV."
/// The prompt card's tag chips (mockup 09) — words the coach can later correlate; display only.
public nonisolated let journalPromptTags = ["Sleep timing", "Work stress", "Late meal", "Alcohol", "Illness"]
/// "3/5" for today's mood, "—" when today has no entry with a mood.
public nonisolated func journalMoodTileText(score: Int?) -> String { score.map { "\($0)/5" } ?? "—" }

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
            .frame(minHeight: JIRowMetrics.minHeight - 2 * JIRowMetrics.verticalPadding)
            .padding(.vertical, JIRowMetrics.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableScale)
        // W-GUI J1: outside a List there is no swipe action; the delete lives in the context menu.
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
                .accessibilityIdentifier("journal-entry-delete")
        }
        .accessibilityAction(named: "Delete", onDelete)
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
