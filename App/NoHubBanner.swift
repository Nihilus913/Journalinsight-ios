import SwiftUI
import JIDesign

/// W-OFFLINE2 OFF2-1 (B-50 slice 2): with no hub the app runs on the on-device provider, so the
/// connect prompt is this one-line banner above Today (plus Settings › Hub), never a full-screen
/// replacement of Today/Recovery. The action is a CTA (rule 6: info blue, not green).
struct NoHubBanner: View {
    static let title = "On-device mode"
    static let detail = "Apple Health only — connect the hub for Garmin, nutrition and plans."
    static let actionTitle = "Connect hub"

    let onConnect: () -> Void
    @Environment(\.jiTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "iphone").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title).jiFont(.footnote, weight: .semibold)
                Text(Self.detail).jiFont(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(Self.actionTitle, action: onConnect)
                .jiFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.color(.info))
                .buttonStyle(.pressableScale)
                .accessibilityIdentifier("today.noHub.connect")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.noHubBanner")
    }
}
