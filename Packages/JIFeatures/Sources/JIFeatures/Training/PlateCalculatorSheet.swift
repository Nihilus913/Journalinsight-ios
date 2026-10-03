import SwiftUI
import JIDesign

/// W-B38-B B-9 — the plate calculator sheet, opened from a phone set row's weight: the plates for
/// ONE side, heaviest first, from the user's own inventory (Settings › Plates & bar). An
/// unreachable load says so — never a nearest guess. Native sheet + list (decision 1).
public struct PlateCalculatorSheet: View {
    private let model: PlateCalculatorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: PlateCalculatorViewModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(model.headline).font(.headline)
                    Text(model.perSideText)
                        .font(.title3.bold())
                        .foregroundStyle(model.outcome == .notLoadable ? Color.secondary : Color.primary)
                        .accessibilityIdentifier("plate-calculator-per-side")
                }
                if case .plates(let side) = model.outcome {
                    Section("Each side, inside out") {
                        ForEach(Array(side.enumerated()), id: \.offset) { _, kg in
                            HStack {
                                Capsule().fill(.tint).frame(width: plateBarWidth(kg), height: 22).accessibilityHidden(true)
                                Text("\(plateKgText(kg)) kg").monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    Text("Bar \(plateKgText(model.inventory.barKg)) kg · plates from Settings › Plates & bar")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Plates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func plateBarWidth(_ kg: Double) -> CGFloat { 12 + CGFloat(min(kg, 25)) * 4 }
}

#Preview("Plates · 52.5") {
    PlateCalculatorSheet(model: PlateCalculatorViewModel(totalKg: 52.5, inventory: .standard))
}
