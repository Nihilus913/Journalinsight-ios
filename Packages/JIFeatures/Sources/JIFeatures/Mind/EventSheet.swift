import SwiftUI
import JIPersistence
import JIDesign

/// Add sheet for episodic health events (migraine, vomiting, reflux, neck pain, other) — oracle
/// `EventSheet.tsx`. Tracking only — neutral, descriptive copy, no clinical-sounding verdicts.
public struct EventSheet: View {
    @Bindable var model: MindViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var type: MindEventType = .migraine
    @State private var timeLocal: String = EventSheet.nowHHMM()
    @State private var severity: Int = 3
    @State private var prodrome: Set<String> = []
    @State private var triggers: String = ""
    @State private var note: String = ""
    @State private var saving = false

    public init(model: MindViewModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(MindEventType.allCases, id: \.self) { t in
                            Text(eventTypeLabel(t)).tag(t)
                        }
                    }
                    .accessibilityLabel("Type")
                }
                Section("Time") {
                    TextField("HH:MM", text: $timeLocal).autocorrectionDisabled()
                        .accessibilityLabel("Time")
                        .accessibilityHint("Hours and minutes, 24-hour clock")
                }
                Section("Severity") {
                    Picker("Severity", selection: $severity) {
                        ForEach(1...5, id: \.self) { s in Text("\(s)").tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Severity")
                    .accessibilityValue("\(severity)")
                }
                Section("What preceded it?") {
                    ForEach(PRODROME_OPTIONS, id: \.self) { opt in
                        Toggle(opt, isOn: Binding(
                            get: { prodrome.contains(opt) },
                            set: { checked in
                                if checked { prodrome.insert(opt) } else { prodrome.remove(opt) }
                            }
                        ))
                        .accessibilityLabel(opt)
                    }
                }
                Section("Triggers") {
                    TextField("e.g. bright light, skipped meal", text: $triggers)
                        .accessibilityLabel("Triggers")
                }
                Section("Note (optional)") {
                    TextField("Anything else worth noting", text: $note, axis: .vertical).lineLimit(2...5)
                        .accessibilityLabel("Note")
                }
            }
            .accessibilityIdentifier("event-sheet-panel")
            .navigationTitle("Log an event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("event-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }.disabled(saving)
                        .accessibilityIdentifier("event-save")
                }
            }
        }
    }

    private func save() async {
        saving = true
        let n = NewMindEvent(
            date: todayISOString(),
            timeLocal: timeLocal.trimmingCharacters(in: .whitespaces),
            type: type,
            severity: severity,
            prodrome: Array(prodrome),
            triggers: triggers.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let ok = await model.addEvent(n)
        saving = false
        if ok { dismiss() }
    }

    static func nowHHMM(now: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
