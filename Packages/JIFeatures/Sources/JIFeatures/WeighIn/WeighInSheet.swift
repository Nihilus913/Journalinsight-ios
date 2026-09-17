import SwiftUI
import JICore
import JIDesign

/// W3b-L4 (P-weigh-in), mirrors the weigh-in part of `mobile/src/components/nutrition/LogSheet.tsx`
/// (`SheetView == "weight"`): a weight logged here closes the sheet immediately on save — no
/// confirm/undo step (a weigh-in has no undo path, same as the oracle). CLAUDE.md rule 5: the field
/// starts empty (never a placeholder "0"), and Save is disabled until the typed text parses to a
/// strictly-positive number, so a zero weight can never reach `WeighInViewModel.submit`.
public struct WeighInSheet: View {
    @Bindable private var model: WeighInViewModel
    @State private var weightText = ""
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(model: WeighInViewModel, onSaved: @escaping () -> Void = {}) {
        self.model = model; self.onSaved = onSaved
    }

    private var parsedWeightKg: Double? {
        guard let value = Double(weightText), value > 0 else { return nil }
        return value
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch model.state {
                case .failure(let message):
                    Surface { Text(message).font(.footnote).foregroundStyle(JIColor.danger) }
                case .queued:
                    Surface { Text("Saved — will sync once the hub is reachable.").font(.footnote).foregroundStyle(JIColor.muted) }
                case .submitting:
                    Surface { HStack { ProgressView(); Text("Saving…").foregroundStyle(JIColor.muted) } }
                case .idle, .success:
                    EmptyView()
                }

                TextField("Weight (kg)", text: $weightText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .padding()
                    .background(JIColor.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(JIColor.text)

                Button {
                    guard let weightKg = parsedWeightKg else { return }
                    Task {
                        if await model.submit(weightKg: weightKg) {
                            onSaved(); dismiss()
                        }
                    }
                } label: {
                    Text("Save weight").frame(maxWidth: .infinity).padding()
                        .background(JIColor.info, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(JIColor.bg)
                }
                .buttonStyle(.pressableScale)
                .disabled(model.state == .submitting || parsedWeightKg == nil)

                Spacer()
            }
            .padding(20)
            .background(JIColor.bg)
            .navigationTitle("Log weight")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
