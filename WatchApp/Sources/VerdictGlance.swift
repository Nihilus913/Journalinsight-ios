import SwiftUI
import JIDesign
import JISnapshot

/// Maps `HubSnapshot.verdictTone`'s wire string ("go"/"amber"/"red"/"muted",
/// per JISnapshot/HubSnapshot.swift's doc comment on `verdictTone`) to a colour
/// role, resolved through the active theme (B-33). Unknown strings fall back to
/// muted — never a guess at go/red.
public func verdictToneColor(_ tone: String, theme: JITheme = .native) -> Color {
    switch tone {
    case "go": theme.color(.go)
    case "amber": theme.color(.reduced)
    case "red": theme.color(.danger)
    default: theme.color(.muted)
    }
}

/// DESIGN-6 / rule 5: never render a bare/zero verdict. No snapshot yet ->
/// "No data yet", never an empty word or a "—" standing in for GO/REDUCED.
public nonisolated func verdictGlanceAccessibilityLabel(_ snapshot: HubSnapshot?) -> String {
    guard let snapshot else { return "Verdict, no data yet" }
    let parts = [snapshot.verdictWord, snapshot.verdictSession].filter { !$0.isEmpty }
    return "Verdict " + parts.joined(separator: " ")
}

/// First glance: today's morning verdict (GO / REDUCED / …), colored by tone.
public struct VerdictGlance: View {
    let snapshot: HubSnapshot?
    @Environment(\.jiTheme) private var theme
    public init(snapshot: HubSnapshot?) { self.snapshot = snapshot }

    public var body: some View {
        Surface(level: 1, padding: 12) {
            VStack(spacing: 6) {
                if let snapshot {
                    Text(snapshot.verdictWord)
                        .jiFont(.title, weight: .bold, design: .rounded)   // W9.5-L4: JITypography token (26pt), Dynamic-Type scaled — no fixed sizes (W8-L3 rule)
                        .foregroundStyle(verdictToneColor(snapshot.verdictTone, theme: theme))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if !snapshot.verdictSession.isEmpty {
                        Text(snapshot.verdictSession)
                            .jiFont(.micro)
                            .foregroundStyle(theme.color(.muted))
                            .lineLimit(1)
                    }
                    if let date = snapshot.verdictDate {
                        Text(date).jiFont(.micro).foregroundStyle(theme.color(.muted))
                    }
                } else {
                    SkeletonBlock(width: 90, height: 26)
                    Text("No data yet").jiFont(.micro).foregroundStyle(theme.color(.muted))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(verdictGlanceAccessibilityLabel(snapshot))
    }
}
