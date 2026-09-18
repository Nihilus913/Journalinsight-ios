import SwiftUI
import JIPersistence
import JIDesign

/// The Mind screen — oracle `app/mind.tsx`. On-device only (no hub calls this wave). "A quiet
/// place to note how you're doing and log the odd rough patch — for spotting patterns over time,
/// nothing more. Everything stays on your device."
public struct MindView: View {
    @Bindable var model: MindViewModel
    @State private var checkInOpen = false
    @State private var eventOpen = false
    @State private var who5Open = false

    public init(model: MindViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("A quiet place to note how you're doing and log the odd rough patch — for spotting patterns over time, nothing more. Everything stays on your device.")
                    .font(.footnote).foregroundStyle(JIColor.muted)

                switch model.phase {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .error(let msg):
                    Surface { Text(msg).foregroundStyle(JIColor.danger) }
                case .loaded:
                    loaded
                }
            }
            .padding(16)
        }
        .background(JIColor.bg)
        .navigationTitle("Mind")
        .task { if model.phase == .idle { await model.load() } }
        .sheet(isPresented: $checkInOpen) { CheckInSheet(model: model) }
        .sheet(isPresented: $eventOpen) { EventSheet(model: model) }
        .sheet(isPresented: $who5Open) { Who5Sheet(model: model) }
    }

    @ViewBuilder
    private var loaded: some View {
        MindSnapshotCard(checkin: model.today)

        Surface(level: 1, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("TODAY").font(.caption.bold()).foregroundStyle(JIColor.muted)
                if model.checkedInToday, let today = model.today {
                    Text("Checked in today · stress \(today.stress)/5 · energy \(today.energy)/5")
                        .foregroundStyle(JIColor.text)
                    Button("Update today's check-in") { checkInOpen = true }.buttonStyle(.pressableScale)
                        .accessibilityIdentifier("mind-update-checkin")
                } else {
                    Text("How are you today? Takes about 10 seconds.").foregroundStyle(JIColor.text)
                    Button("Daily check-in") { checkInOpen = true }.buttonStyle(.pressableScale)
                        .accessibilityIdentifier("mind-daily-checkin")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }

        Surface(level: 1, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WEEKLY WELL-BEING").font(.caption.bold()).foregroundStyle(JIColor.muted)
                if let who5 = model.latestWho5 {
                    Text("Last score \(who5.pct)/100 · \(who5.date)").foregroundStyle(JIColor.text)
                }
                if model.who5Due {
                    Text("Your weekly check-in is ready — about a minute.").font(.footnote).foregroundStyle(JIColor.muted)
                    Button("Take the weekly check-in") { who5Open = true }.buttonStyle(.pressableScale)
                        .accessibilityIdentifier("mind-who5")
                } else {
                    Button("Take it again") { who5Open = true }.buttonStyle(.pressableScale)
                        .accessibilityIdentifier("mind-who5-again")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }

        Surface(level: 1, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("EVENTS").font(.caption.bold()).foregroundStyle(JIColor.muted)
                Button("+ Log an event") { eventOpen = true }.buttonStyle(.pressableScale)
                    .accessibilityIdentifier("mind-log-event")
                if model.events.isEmpty {
                    Text("No events logged.").font(.footnote).foregroundStyle(JIColor.muted)
                } else {
                    ForEach(model.events, id: \.id) { e in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(eventTypeLabel(e.type)) · sev \(e.severity)/5").font(.subheadline.bold()).foregroundStyle(JIColor.text)
                                    .accessibilityLabel(eventTypeLabel(e.type))
                                    .accessibilityValue("Severity \(e.severity) of 5")
                                Text(eventSubtitle(e)).font(.footnote).foregroundStyle(JIColor.muted)
                            }
                            Spacer()
                            Button {
                                Task { await model.deleteEvent(e.id) }
                            } label: {
                                Image(systemName: "xmark").foregroundStyle(JIColor.danger)
                            }
                            .accessibilityLabel("Delete \(eventTypeLabel(e.type)) event")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func eventSubtitle(_ e: MindEvent) -> String {
        var s = "\(e.date) \(e.timeLocal)"
        if !e.prodrome.isEmpty { s += " · \(e.prodrome.joined(separator: ", "))" }
        return s
    }
}
