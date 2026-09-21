import SwiftUI
import JIPersistence
import JIDesign

/// ≤10s daily mental-health check-in — oracle `CheckInSheet.tsx`. Mood + stress/energy (1-5) +
/// optional note, plus an optional "on my meds today?" toggle that reveals three more 1-5 axes
/// (irritability/restlessness/appetite — the `dosed` toggle exists because Concerta inflates
/// daytime HR/stress, memory `user_methylphenidate`). One row per day: prefills from
/// `model.today` so re-opening the sheet edits rather than duplicates.
///
/// Tracking only, never diagnosis: all copy here is neutral/descriptive. No crisis text or
/// disclaimer here — that lives on the Mind screen itself (oracle parity).
public struct CheckInSheet: View {
    @Bindable var model: MindViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mood: JIPersistence.Mood?
    @State private var stress: Int?
    @State private var energy: Int?
    @State private var note: String = ""
    @State private var dosed = false
    @State private var irritability: Int?
    @State private var restlessness: Int?
    @State private var appetite: Int?
    @State private var saving = false

    public init(model: MindViewModel) { self.model = model }

    private var canSave: Bool { stress != nil && energy != nil }

    public var body: some View {
        NavigationStack {
            Form {
                Section("How's your mood?") {
                    Picker("Mood", selection: $mood) {
                        Text("—").tag(JIPersistence.Mood?.none)
                        ForEach(JIPersistence.Mood.allCases, id: \.self) { m in
                            Text("\(m.emoji) \(m.rawValue.capitalized)").tag(JIPersistence.Mood?.some(m))
                        }
                    }
                    // §8.2/§8.4: an inline picker instead of the menu style — the choices are a
                    // short fixed set, and inline rows reflow at AX sizes where a menu label has
                    // to be measured against a popover it can no longer fit.
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityLabel("Mood")
                }
                scoreSection("Stress", value: $stress)
                scoreSection("Energy", value: $energy)
                Section("Note (optional)") {
                    TextField("Anything you want to remember about today", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Note")
                }
                Section {
                    Toggle("On my meds today?", isOn: $dosed)
                        .accessibilityLabel("On my meds today?")
                }
                if dosed {
                    scoreSection("Irritability", value: $irritability)
                    scoreSection("Restlessness", value: $restlessness)
                    scoreSection("Appetite", value: $appetite)
                }
            }
            .accessibilityIdentifier("checkin-sheet-panel")
            .navigationTitle("Daily check-in")
            .jiTheme(.native)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("checkin-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(!canSave || saving)
                        .accessibilityIdentifier("checkin-save")
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func scoreSection(_ label: String, value: Binding<Int?>) -> some View {
        Section(label) {
            Picker(label, selection: value) {
                Text("—").tag(Int?.none)
                ForEach(1...5, id: \.self) { n in Text("\(n)").tag(Int?.some(n)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Oracle `CheckInSheet.tsx` labels each segment `"<label> <n>"`; SwiftUI's segmented
            // picker is one element, so the axis name is the label and the pick is the value.
            .accessibilityLabel(label)
            .accessibilityValue(value.wrappedValue.map { "\($0)" } ?? "Not set")
        }
    }

    private func prefill() {
        let today = model.today
        mood = today?.mood
        stress = today?.stress
        energy = today?.energy
        note = today?.note ?? ""
        dosed = today?.dosed ?? false
        irritability = today?.irritability
        restlessness = today?.restlessness
        appetite = today?.appetite
    }

    private func save() async {
        guard canSave else { return }
        saving = true
        let payload = NewCheckIn(
            date: todayISOString(),
            mood: mood,
            stress: stress!,
            energy: energy!,
            dosed: dosed,
            irritability: dosed ? irritability : nil,
            restlessness: dosed ? restlessness : nil,
            appetite: dosed ? appetite : nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let ok = await model.upsertCheckin(payload)
        saving = false
        if ok { dismiss() }
    }
}
