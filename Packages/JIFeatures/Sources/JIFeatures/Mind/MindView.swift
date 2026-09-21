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
            Section {
                switch model.phase {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .error(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(theme.color(.danger))
                case .loaded:
                    MindSnapshotCard(checkin: model.today)
                }
            } footer: {
                Text("A quiet place to note how you're doing and log the odd rough patch — for spotting patterns over time, nothing more. Everything stays on your device.")
            }

            if case .loaded = model.phase { loaded }
        }
        .jiNativeFormChrome()
        .jiTheme(.native)
        .navigationTitle("Mind")
        .task { if model.phase == .idle { await model.load() } }
        .sheet(isPresented: $checkInOpen) { CheckInSheet(model: model).jiNativeSheetSizing() }
        .sheet(isPresented: $eventOpen) { EventSheet(model: model).jiNativeSheetSizing() }
        .sheet(isPresented: $who5Open) { Who5Sheet(model: model).jiNativeSheetSizing() }
    }

    /// §2b.2: every group below the snapshot is a real `List` section — system header, 44-pt
    /// rows, swipe-to-delete on an event instead of a bespoke ✕ button.
    @ViewBuilder
    private var loaded: some View {
        Section("Today") {
            if model.checkedInToday, let today = model.today {
                JIRow(title: "Checked in today", subtitle: "stress \(today.stress)/5 · energy \(today.energy)/5", systemImage: "checkmark.circle")
                Button("Update today's check-in") { checkInOpen = true }
                    .accessibilityIdentifier("mind-update-checkin")
            } else {
                JIRow(title: "How are you today?", subtitle: "Takes about 10 seconds.", systemImage: "questionmark.circle")
                Button("Daily check-in") { checkInOpen = true }
                    .accessibilityIdentifier("mind-daily-checkin")
            }
        }

        Section {
            if let who5 = model.latestWho5 {
                JIRow(title: "Last score", subtitle: who5.date, systemImage: "chart.bar") { Text("\(who5.pct)/100") }
            }
            if model.who5Due {
                Button("Take the weekly check-in") { who5Open = true }
                    .accessibilityIdentifier("mind-who5")
            } else {
                Button("Take it again") { who5Open = true }
                    .accessibilityIdentifier("mind-who5-again")
            }
        } header: {
            Text("Weekly well-being")
        } footer: {
            if model.who5Due { Text("Your weekly check-in is ready — about a minute.") }
        }

        Section {
            Button("Log an event", systemImage: "plus") { eventOpen = true }
                .accessibilityIdentifier("mind-log-event")
            if model.events.isEmpty {
                Text("No events logged.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
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
            Text("Events")
        }
    }

    private func eventSubtitle(_ e: MindEvent) -> String {
        var s = "\(e.date) \(e.timeLocal)"
        if !e.prodrome.isEmpty { s += " · \(e.prodrome.joined(separator: ", "))" }
        return s
    }
}
