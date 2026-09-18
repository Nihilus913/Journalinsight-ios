import SwiftUI
import JICore
import JIDesign

/// (W3a-L2, mirrors `mobile/src/components/nutrition/LogSheet.tsx`, trimmed to the one-tap
/// template flow — the manual item-entry form is out of this wave's scope). PINNED FOOD-LOG
/// CONTRACT: 409/502 show the oracle's copy verbatim via `LogSheetViewModel.describe`.
public struct LogSheet: View {
    @Bindable private var model: LogSheetViewModel
    /// W3b-L4 (P-weigh-in) — the "weight" entry the RN `LogSheet.tsx` menu has alongside food
    /// logging. `nil` when the caller hasn't wired a `WeighInViewModel` yet (e.g. an existing call
    /// site not yet updated for this wave): the row is simply omitted rather than presenting a
    /// half-configured sheet.
    private let weighInModel: WeighInViewModel?
    let onLogged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingWeighIn = false

    /// Mirrors the oracle's `BREAKFAST_TEMPLATE_ID` (`mobile/src/data/nutritionTemplates.ts`).
    public static let breakfastTemplateID = "breakfast_default"

    public init(model: LogSheetViewModel, weighInModel: WeighInViewModel? = nil, onLogged: @escaping () -> Void = {}) {
        self.model = model; self.weighInModel = weighInModel; self.onLogged = onLogged
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch model.state {
                case .failure(let message):
                    Surface {
                        Text(message).font(.footnote).foregroundStyle(JIColor.danger)
                            .accessibilityIdentifier("logsheet-error")
                    }
                case .submitting:
                    Surface { HStack { ProgressView(); Text("Logging…").foregroundStyle(JIColor.muted) } }
                        .accessibilityIdentifier("logsheet-submitting")
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
                .accessibilityLabel("Log Standard breakfast")
                .accessibilityIdentifier("logsheet-log-breakfast")

                if let weighInModel {
                    Button {
                        showingWeighIn = true
                    } label: {
                        Text("Log weight").frame(maxWidth: .infinity).padding()
                            .background(JIColor.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(JIColor.text)
                    }
                    .buttonStyle(.pressableScale)
                    // Oracle `LogSheet.tsx` MenuRow: title "Log weight", sub "Push a weigh-in to Garmin".
                    .accessibilityLabel("Log weight")
                    .accessibilityHint("Push a weigh-in to Garmin")
                    .accessibilityIdentifier("logsheet-log-weight")
                    .sheet(isPresented: $showingWeighIn) {
                        WeighInSheet(model: weighInModel, onSaved: onLogged)
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(JIColor.bg)
            .navigationTitle("Log food")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityLabel("Cancel").accessibilityIdentifier("logsheet-cancel") } }
        }
    }
}
