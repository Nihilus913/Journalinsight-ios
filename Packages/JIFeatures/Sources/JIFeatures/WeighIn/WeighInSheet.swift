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
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the applying view.
    private let theme = JITheme.native

    public init(model: WeighInViewModel, onSaved: @escaping () -> Void = {}) {
        self.model = model; self.onSaved = onSaved
    }

    private var parsedWeightKg: Double? {
        guard let value = Double(weightText), value > 0 else { return nil }
        return value
    }

    public var body: some View {
        NavigationStack {
            nativeContent
                .navigationTitle("Log weight")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityLabel("Cancel").accessibilityIdentifier("weighin-cancel") } }
        }
        .jiTheme(.native)
        #if os(iOS)
        // §8.2: form-sized on a regular-width canvas instead of full-screen.
        .presentationSizing(.form)
        #endif
    }

    /// §8.5: the sheet's composition without its navigation shell — what the sweep renders.
    @ViewBuilder var nativeContent: some View {
            VStack(spacing: 16) {
                switch model.state {
                case .failure(let message):
                    Surface { Text(message).jiFont(.footnote).foregroundStyle(theme.color(.danger)) }
                        .accessibilityIdentifier("weighin-error")
                case .queued:
                    Surface { Text("Saved — will sync once the hub is reachable.").jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
                        .accessibilityIdentifier("weighin-queued")
                case .submitting:
                    Surface { HStack { ProgressView(); Text("Saving…").foregroundStyle(theme.color(.muted)) } }
                case .idle, .success:
                    EmptyView()
                }

                TextField("Weight (kg)", text: $weightText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .padding()
                    .background(theme.color(.control), in: RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                    .foregroundStyle(theme.color(.text))
                    // Oracle `LogSheet.tsx` TextField label, verbatim.
                    .accessibilityLabel("Weight (kg)")
                    .accessibilityIdentifier("weighin-weight-field")

                Button {
                    guard let weightKg = parsedWeightKg else { return }
                    Task {
                        if await model.submit(weightKg: weightKg) {
                            onSaved(); dismiss()
                        }
                    }
                } label: {
                    Text("Save weight").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.color(.info))
                .disabled(model.state == .submitting || parsedWeightKg == nil)
                .accessibilityLabel("Save weight")
                .accessibilityIdentifier("weighin-save")

                Spacer()
            }
            .padding(20)
            .readableColumn()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.color(.bg))
    }
}
