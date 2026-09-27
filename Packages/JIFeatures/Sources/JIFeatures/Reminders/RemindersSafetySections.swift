import SwiftUI
import JIDesign

/// Board `5 Settings/08 Reminders` — SAFETY group (8-week HR cap check). Off and disabled when
/// the user has no cap (Toby 2026-09-24: the cap is optional, nothing to re-check without one).
public struct RemindersSafetySection: View {
    @Environment(\.jiTheme) private var theme
    private let model: RemindersViewModel
    public init(model: RemindersViewModel) { self.model = model }

    public var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.hrCapCheckDue != nil },
                                 set: { on in Task { await model.setHrCapCheckEnabled(on) } })) {
                JIRow(title: ReminderKind.hrCapCheck.sectionTitle, subtitle: model.hrCapCheckLine,
                      systemImage: ReminderKind.hrCapCheck.boardSymbol)
            }
            .tint(theme.color(.info))
            .disabled(model.hrCapBpm == nil)
            .accessibilityLabel(ReminderKind.hrCapCheck.sectionTitle)
            .accessibilityValue(model.hrCapCheckLine)
            .accessibilityIdentifier("reminders.hrCapCheck")
        } header: {
            Text("Safety")
        } footer: {
            if let cap = model.hrCapBpm {
                Text("JI asks whether \(cap) is still right. It never changes the number for you.")
            } else {
                Text(RemindersCopy.noCapFooter)
            }
        }
    }
}

/// Board `5 Settings/08 Reminders` — MEDICATION group (Name, Dose, Time, Works for about).
/// "Pick from Apple Health" is added by LD only if the device spike passes.
public struct RemindersMedicationSection: View {
    private let model: RemindersViewModel
    @State private var draft = MedicationEntry()
    public init(model: RemindersViewModel) { self.model = model }

    public var body: some View {
        MedicationFieldsSection(entry: $draft)
            // Seed from the stored entry once the model has loaded (not before: an early empty
            // draft must never overwrite what the user saved).
            .task(id: model.loaded) { if model.loaded { draft = model.medication ?? MedicationEntry() } }
            .onChange(of: draft) { _, next in
                guard model.loaded else { return }
                let stored: MedicationEntry? = next.isNamed ? next : nil
                guard stored != model.medication else { return }
                Task { await model.setMedication(stored) }
            }
    }
}
