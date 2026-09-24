import SwiftUI
import JIPersistence
import JIDesign

/// The Mind screen — oracle `app/mind.tsx`. On-device only (no hub calls this wave). "A quiet
/// place to note how you're doing and log the odd rough patch — for spotting patterns over time,
/// nothing more. Everything stays on your device."
public struct MindView: View {
    @Environment(\.jiTheme) private var theme
    @Bindable var model: MindViewModel
    @State private var checkInOpen = false
    @State private var eventOpen = false
    @State private var who5Open = false

    public init(model: MindViewModel) { self.model = model }

    public var body: some View {
        List {
            switch model.phase {
            case .idle, .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .error(let msg):
                Section { Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(theme.color(.danger)) }
            case .loaded:
                loaded
            }
        }
        .jiNativeFormChrome()
        .readableColumn()
        .jiTheme(.native)
        .navigationTitle("Mind")
        .navigationSubtitle("On this phone only")   // B-57 W1 board 4/03
        .task { if model.phase == .idle { await model.load() } }
        .sheet(isPresented: $checkInOpen) { CheckInSheet(model: model).jiNativeSheetSizing() }
        .sheet(isPresented: $eventOpen) { EventSheet(model: model).jiNativeSheetSizing() }
        .sheet(isPresented: $who5Open) { Who5Sheet(model: model).jiNativeSheetSizing() }
    }

    /// B-57 W1 board 4/03: a Today card (stress · energy from today's check-in, the mood as a
    /// five-step track, the check-in button), the WHO-5 "Last score" card against the 50 screening
    /// line, then Events. Descriptive only — never a verdict word or verdict colour (E9 rail).
    @ViewBuilder
    private var loaded: some View {
        let summary = mindTodaySummary(model.today)
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Today", systemImage: "waveform.path")
                    .jiFont(.subheadline, weight: .semibold, tint: .text)
                HStack(alignment: .top, spacing: 28) {
                    MindScaleValue(label: "Stress", value: summary.stress)
                    MindScaleValue(label: "Energy", value: summary.energy)
                }
                BoardStatusLabel(word: summary.statusWord, systemImage: model.checkedInToday ? "checkmark" : "minus",
                                 role: model.checkedInToday ? .info : .muted)
                    .accessibilityIdentifier("mind-today-status")
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { step in
                        Capsule()
                            .fill(summary.moodStep.map { step <= $0 } == true ? theme.color(.info) : theme.color(.control))
                            .frame(height: 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mood")
                .accessibilityValue(summary.moodStep.map { "\($0) of 5" } ?? "No data")
                if model.checkedInToday {
                    Text(model.snapshot.headline).jiFont(.subheadline, tint: .muted)
                }
                Button { checkInOpen = true } label: {
                    Text(model.checkedInToday ? "Update today\u{2019}s check-in" : "Daily check-in")
                        .jiFont(.subheadline, weight: .bold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.color(.info))
                .accessibilityIdentifier(model.checkedInToday ? "mind-update-checkin" : "mind-daily-checkin")
            }
            .padding(.vertical, 6)
        }

        Section {
            Who5ScoreCard(entry: model.latestWho5)
            Button(model.who5Due ? "Take the weekly check-in" : "Take it again") { who5Open = true }
                .accessibilityIdentifier(model.who5Due ? "mind-who5" : "mind-who5-again")
        } header: {
            BoardSectionHeader("Weekly well-being", caption: "WHO-5")
        } footer: {
            if model.who5Due { Text("Your weekly check-in is ready — about a minute.") }
        }

        Section {
            if model.events.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Migraine · reflux · other").jiFont(.subheadline, tint: .text)
                    BoardStatusLabel(word: "None logged", systemImage: "minus", role: .muted)
                }
                .accessibilityElement(children: .combine)
            } else {
                ForEach(model.events, id: \.id) { e in
                    JIRow(title: "\(eventTypeLabel(e.type)) · sev \(e.severity)/5", subtitle: eventSubtitle(e))
                        .accessibilityLabel(eventTypeLabel(e.type))
                        .accessibilityValue("Severity \(e.severity) of 5")
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { Task { await model.deleteEvent(e.id) } }
                                .accessibilityLabel("Delete \(eventTypeLabel(e.type)) event")
                        }
                }
            }
        } header: {
            BoardSectionHeader(title: "Events") {
                Button("Log an event") { eventOpen = true }
                    .buttonStyle(.plain)
                    .jiFont(.subheadline, weight: .semibold, tint: .info)
                    .accessibilityIdentifier("mind-log-event")
            }
        } footer: {
            Text("A quiet place to note how you're doing and log the odd rough patch — for spotting patterns over time, nothing more. Everything stays on your device.")
        }
    }

    private func eventSubtitle(_ e: MindEvent) -> String {
        var s = "\(e.date) \(e.timeLocal)"
        if !e.prodrome.isEmpty { s += " · \(e.prodrome.joined(separator: ", "))" }
        return s
    }
}

/// One of the Today card's two numbers: "3/5", or "—" when there is no check-in (rule 5).
private struct MindScaleValue: View {
    let label: String
    let value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(String.init) ?? "—").jiNumeral(.numeralCompact, weight: .bold, tint: value == nil ? .muted : .info)
                if value != nil { Text("/5").jiFont(.footnote, tint: .muted) }
            }
            Text(label).jiFont(.subheadline, tint: .muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "\($0) of 5" } ?? "Not checked in")
    }
}

/// The WHO-5 "Last score" card: the percentage against the 50 screening line. No score yet =
/// "—" and "No data".
private struct Who5ScoreCard: View {
    let entry: Who5Entry?
    @Environment(\.jiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BoardSummaryCard(
                systemImage: "chart.bar", title: "Last score",
                trailing: entry.flatMap { JournalCalendarZurich.date(fromISODay: $0.date) }
                    .map { JournalCalendarZurich.formatter("d MMM").string(from: $0) },
                value: entry.map { "\($0.pct)" }, unit: "/ 100",
                status: entry.map { BoardStatus(word: who5ScoreWord(pct: $0.pct), systemImage: $0.pct > 50 ? "checkmark" : "minus",
                                                 role: $0.pct > 50 ? .info : .muted) }
                    ?? BoardStatus(word: "No data", systemImage: "minus", role: .muted)
            )
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.color(.control))
                    if let pct = entry?.pct {
                        Capsule().fill(theme.color(.info)).frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100)
                    }
                    Rectangle().fill(theme.color(.text)).frame(width: 2).offset(x: geo.size.width / 2 - 1)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("0"); Spacer(); Text("50 · screening line"); Spacer(); Text("100")
                }
                Text("50 = screening line")
            }
            .jiFont(.footnote, tint: .muted)
            .accessibilityHidden(true)
        }
    }
}
