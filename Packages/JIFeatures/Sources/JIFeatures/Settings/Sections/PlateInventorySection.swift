import SwiftUI
import JIDesign
import JIPersistence

// W-B38-B B-9: Settings › Plates & bar — the bar weight and the plate pairs the plate calculator
// uses (first launch = standard plates + 1.25 / 2.5 kg microplates; remove every plate = no calculator).
public struct PlateInventorySection: SettingsSection {
    public nonisolated static let sectionId = "b38b.plates"
    public let id = Self.sectionId
    public let title = "Plates & bar"
    public let systemImage = "scalemass"
    public let sortKey = SettingsSortKey.preferences + 60
    public let group = SettingsGroupId.home
    public init() {}
    public var body: some View { PlateInventoryRows() }
}

private struct PlateInventoryRows: View {
    @Environment(SettingsViewModel.self) private var settings
    var body: some View { PlateInventoryForm(model: PlateInventoryViewModel(prefs: settings.prefs)) }
}

struct PlateInventoryForm: View {
    @State var model: PlateInventoryViewModel
    @State private var barText = ""
    @State private var newSize = ""

    var body: some View {
        Section {
            HStack {
                Text("Bar")
                Spacer()
                TextField("kg", text: $barText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing).frame(maxWidth: 80)
                    .onSubmit { model.setBar(text: barText) }
                    .accessibilityIdentifier("plates-bar-kg")
                Text("kg").foregroundStyle(.secondary)
            }
            if let error = model.barError { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: { Text("Bar") }
        Section {
            if model.inventory.pairs.isEmpty {
                Text("No plates — the plate calculator is off.").foregroundStyle(.secondary)
            }
            ForEach(model.inventory.sizeRows) { row in
                Stepper(value: Binding(get: { row.pairs }, set: { model.setCount($0, for: row.kg) }), in: 0...10) {
                    HStack {
                        Text("\(plateKgText(row.kg)) kg").monospacedDigit()
                        Spacer()
                        Text(row.pairs == 1 ? "1 pair" : "\(row.pairs) pairs").foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("plates-size-\(plateKgText(row.kg))")
            }
            HStack {
                TextField("Add a plate size (kg)", text: $newSize)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Button("Add") { if model.addSize(text: newSize) { newSize = "" } }
                    .disabled(newSize.isEmpty)
            }
            Button("Reset to standard plates") { model.resetToStandard(); barText = plateKgText(model.inventory.barKg) }
            if let error = model.saveError { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Plates (pairs)")
        } footer: {
            Text("The plate calculator on a set's weight shows the plates for one side from these.")
        }
        .onAppear { barText = plateKgText(model.inventory.barKg) }
    }
}
