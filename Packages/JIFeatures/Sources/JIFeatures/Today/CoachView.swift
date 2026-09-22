import SwiftUI
import JICore
import JIDesign

/// B-57 §2 Coach: why the verdict (≤3 signals) and the one change for today, then **Got it**.
/// `readOnly` is the Day-view re-open from the summary line (no button, nothing advances).
public struct CoachView: View {
    let content: CoachContent
    let verdict: VerdictParts
    let readOnly: Bool
    let onAcknowledge: () -> Void
    @Environment(\.jiTheme) private var theme

    public init(content: CoachContent, verdict: VerdictParts, readOnly: Bool = false, onAcknowledge: @escaping () -> Void) {
        self.content = content; self.verdict = verdict; self.readOnly = readOnly; self.onAcknowledge = onAcknowledge
    }

    public var body: some View {
        Surface(level: 1, padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                // The full rationale stays one tap away, as the hero had it. Attached to the "why"
                // block only (not the whole card) so "Got it" stays its own accessible button.
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why \(verdict.word.lowercased())")
                        .jiFont(.cardTitle, weight: .semibold).foregroundStyle(theme.color(.text))
                    ForEach(content.signals, id: \.self) { s in
                        Label(s, systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon).imageScale(.small)
                            .jiFont(.body).foregroundStyle(theme.color(.text))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gateRationaleDestination()
                Divider().overlay(theme.color(.hairlineNested))
                Text("One change today").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                Text(content.change).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.coach.change")
                if !readOnly {
                    Button { onAcknowledge() } label: {
                        Text("Got it").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(theme.color(.info)).controlSize(.large)
                    .accessibilityIdentifier("today.coach.gotIt")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
