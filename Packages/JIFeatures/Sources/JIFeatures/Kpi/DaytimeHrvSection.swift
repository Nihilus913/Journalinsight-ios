import SwiftUI
import JIDesign

/// B-57 W4 — board `2 Monitor/03 KpiDetail`: the "Daytime HRV · On hold · confirm below" row and
/// the "Medication check" card. Manual-entry wording (Apple Health wording arrives with LD only).
/// Daytime HRV is context only (B-65): nothing here changes a verdict.
struct DaytimeHrvSection: View {
    @Bindable var model: KpiDetailViewModel
    private let theme = JITheme.native

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Surface {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { valueText; Spacer(minLength: 8); stateText }
                    VStack(alignment: .leading, spacing: 4) { valueText; stateText }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("kpi-detail-daytime-hrv")

            if model.showsMedicationCard { card }
        }
    }

    private var valueText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Daytime HRV").jiFont(.body).foregroundStyle(theme.color(.text))
            Text(model.daytimeValueText).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
            if let r = model.daytimeReason { Text(r).jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
        }
    }

    private var stateText: some View {
        Text(model.daytimeState.word).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(model.daytimeState.role))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var card: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Medication check", systemImage: "pills").jiFont(.subheadline, weight: .semibold)
                        .foregroundStyle(theme.color(.text))
                    Spacer()
                    if model.medication?.answer == .unconfirmed {
                        Text("To confirm").jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.reduced))
                    }
                }
                if model.medication?.answer == .unconfirmed {
                    Text(model.medicationCardBody).jiFont(.body).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Yes, I take it") { model.answerMedication(true) }
                            .buttonStyle(.jiPrimary)
                            .accessibilityIdentifier("kpi-detail-med-yes")
                        Button("No") { model.answerMedication(false) }
                            .buttonStyle(.jiSecondary)
                            .accessibilityIdentifier("kpi-detail-med-no")
                    }
                    Text("Yes: daytime HRV is set aside during those hours. No: it counts like any other reading.")
                        .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(model.medication?.answer == .yes
                         ? "You confirmed \(model.medication?.name ?? ""). Daytime HRV: \(model.daytimeState.word.lowercased())."
                         : "You said no. Daytime HRV counts like any other reading.")
                        .jiFont(.body).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                    // DEV-07: a secondary button, not a tinted text link (W-B57-W4 fixer).
                    Button("Change answer") { model.resetMedicationAnswer() }
                        .buttonStyle(.jiSecondary)
                        .accessibilityIdentifier("kpi-detail-med-change")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("kpi-detail-med-card")
    }
}
