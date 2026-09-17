import SwiftUI
import JIDesign
import JISnapshot

/// Maps `HubSnapshot.verdictTone`'s wire string ("go"/"amber"/"red"/"muted",
/// per JISnapshot/HubSnapshot.swift's doc comment on `verdictTone`) to a
/// `JIColor`. Unknown strings fall back to muted — never a guess at go/red.
public func verdictToneColor(_ tone: String) -> Color {
    switch tone {
    case "go": JIColor.go
    case "amber": JIColor.reduced
    case "red": JIColor.danger
    default: JIColor.muted
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
    public init(snapshot: HubSnapshot?) { self.snapshot = snapshot }

    public var body: some View {
        Surface(level: 1, padding: 12) {
            VStack(spacing: 6) {
                if let snapshot {
                    Text(snapshot.verdictWord)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(verdictToneColor(snapshot.verdictTone))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if !snapshot.verdictSession.isEmpty {
                        Text(snapshot.verdictSession)
                            .font(.caption2)
                            .foregroundStyle(JIColor.muted)
                            .lineLimit(1)
                    }
                    if let date = snapshot.verdictDate {
                        Text(date).font(.caption2).foregroundStyle(JIColor.muted)
                    }
                } else {
                    SkeletonBlock(width: 90, height: 26)
                    Text("No data yet").font(.caption2).foregroundStyle(JIColor.muted)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(verdictGlanceAccessibilityLabel(snapshot))
    }
}
