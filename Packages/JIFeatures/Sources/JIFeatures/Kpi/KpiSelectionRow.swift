import SwiftUI
import JIDesign

/// §2b.2 one 44-pt inset-grouped row of the "My KPIs" picker: label + live value + target,
/// accessible up/down reorder, and the include toggle. A plain data-in view so the sweep can
/// render the list from a fixture without a hub-backed view model.
struct KpiSelectionRow: View {
    let label: String, valueText: String, targetText: String?
    let selected: Bool, canMoveUp: Bool, canMoveDown: Bool, showsReorder: Bool
    let identifierSuffix: String
    let onMoveUp: () -> Void, onMoveDown: () -> Void, onToggle: (Bool) -> Void
    @Environment(\.jiTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).jiFont(.subheadline, weight: .bold).foregroundStyle(theme.color(.text))
                Text(valueText).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .accessibilityLabel("\(label), \(valueText)")
                    .accessibilityIdentifier("kpi-row-value-\(identifierSuffix)")
                if let targetText {
                    Text("Target \(targetText)").jiFont(.micro).foregroundStyle(theme.color(.mutedNested))
                }
            }
            Spacer()
            if showsReorder {
                HStack(spacing: 6) {
                    Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                        .disabled(!canMoveUp)
                        .accessibilityLabel("Move \(label) up in My KPIs")
                        .accessibilityIdentifier("kpi-move-up-\(identifierSuffix)")
                    Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                        .disabled(!canMoveDown)
                        .accessibilityLabel("Move \(label) down in My KPIs")
                        .accessibilityIdentifier("kpi-move-down-\(identifierSuffix)")
                }
                .buttonStyle(.pressableScale)
            }
            Toggle(isOn: Binding(get: { selected }, set: onToggle)) { EmptyView() }
                .labelsHidden()
                .accessibilityLabel(selected ? "Remove \(label) from My KPIs" : "Add \(label) to My KPIs")
                .accessibilityIdentifier("kpi-toggle-\(identifierSuffix)")
        }
        .opacity(selected ? 1 : 0.45)
        .frame(minHeight: JIRow<EmptyView>.minHeight)
        .padding(.vertical, 2)
    }
}
