import SwiftUI
import JICore
import JIDesign

/// (W3a-L2, mirrors `mobile/src/components/nutrition/LogSheet.tsx`, trimmed to the one-tap
/// template flow — the manual item-entry form is out of this wave's scope). PINNED FOOD-LOG
/// CONTRACT: 409/502 show the oracle's copy verbatim via `LogSheetViewModel.describe`.
public struct LogSheet: View {
    @Bindable private var model: LogSheetViewModel
    let onLogged: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// Mirrors the oracle's `BREAKFAST_TEMPLATE_ID` (`mobile/src/data/nutritionTemplates.ts`).
    public static let breakfastTemplateID = "breakfast_default"

    public init(model: LogSheetViewModel, onLogged: @escaping () -> Void = {}) {
        self.model = model; self.onLogged = onLogged
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch model.state {
                case .failure(let message):
                    Surface {
                        Text(message).font(.footnote).foregroundStyle(JIColor.danger)
                    }
                case .submitting:
                    Surface { HStack { ProgressView(); Text("Logging…").foregroundStyle(JIColor.muted) } }
                default:
                    EmptyView()
                }

                Button {
                    Task {
                        if await model.submitTemplate(Self.breakfastTemplateID, meal: .breakfast) != nil {
                            onLogged(); dismiss()
                        }
                    }
                } label: {
                    Text("Log Standard breakfast").frame(maxWidth: .infinity).padding()
                        .background(JIColor.info, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(JIColor.bg)
                }
                .buttonStyle(.pressableScale)
                .disabled(model.state == .submitting)

                Spacer()
            }
            .padding(20)
            .background(JIColor.bg)
            .navigationTitle("Log food")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
