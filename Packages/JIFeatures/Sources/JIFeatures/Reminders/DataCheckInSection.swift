import SwiftUI
import JIDesign

// W-B102 C-6 (BP-23a mockup frame 04): Settings › Reminders › "Data-triggered check-in" — one
// toggle, the fixed quiet hours / earliest time, and the rules (read-only in slice 23a).

public nonisolated enum DataCheckInCopy {
    public static let title = "Data-triggered check-in"
    public static let toggle = "Ask me when the data moves"
    public static let toggleCaption = "Local notification · at most once a day"
    public static let quietHours = "Quiet hours · 22:00 – 07:00"
    public static let earliest = "Earliest time · 09:00, after the 05:10 readiness floor"
    public static let footer = "Rules are fixed and deterministic. They read the last 7 mornings and never a model. A check-in never changes the verdict, the gate or dosing."
}

struct DataCheckInSection: View {
    let model: RemindersViewModel
    @Environment(\.jiTheme) private var theme

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.dataCheckInEnabled }, set: { model.setDataCheckInEnabled($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DataCheckInCopy.toggle)
                    Text(DataCheckInCopy.toggleCaption).jiFont(.caption, tint: .muted)
                }
            }
            .accessibilityIdentifier("reminders.dataCheckIn.toggle")
            Text(DataCheckInCopy.quietHours).jiFont(.subheadline, tint: .muted)
            Text(DataCheckInCopy.earliest).jiFont(.subheadline, tint: .muted)
            ForEach(CheckInRule.allCases, id: \.self) { rule in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.title)
                    Text(rule.caption).jiFont(.caption, tint: .muted)
                }
                .opacity(model.dataCheckInEnabled ? 1 : 0.5)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(DataCheckInCopy.title)
        } footer: {
            Text(DataCheckInCopy.footer)
        }
    }
}
