import ActivityKit
import JICore
import JIDesign
import SwiftUI
import WidgetKit

/// Lock-screen / Dynamic Island presentation for `VerdictActivityAttributes`.
/// Reads only `context.state` — never touches `SnapshotStore` directly, so
/// it has no App-Group or Keychain dependency beyond what `LiveActivityController`
/// already fed it.
struct VerdictLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VerdictActivityAttributes.self) { context in
            VerdictActivityLockScreenView(state: context.state)
                .activityBackgroundTint(JIColor.bg)
                .activitySystemActionForegroundColor(JIColor.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.verdictWord)
                        .font(.headline)
                        .foregroundStyle(tone(context.state.verdictTone))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let readiness = context.state.readiness {
                        Text("\(Int(readiness.rounded()))")
                            .font(.headline)
                            .foregroundStyle(JIColor.text)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.verdictSession)
                        .font(.caption)
                        .foregroundStyle(JIColor.muted)
                }
            } compactLeading: {
                Circle().fill(tone(context.state.verdictTone)).frame(width: 10, height: 10)
            } compactTrailing: {
                if let readiness = context.state.readiness {
                    Text("\(Int(readiness.rounded()))")
                        .font(.caption2)
                } else {
                    Text("--").font(.caption2)
                }
            } minimal: {
                Circle().fill(tone(context.state.verdictTone)).frame(width: 8, height: 8)
            }
        }
    }

    private func tone(_ raw: String) -> Color {
        JIColor.color(for: verdictTone(from: raw))
    }
}

/// `HubSnapshot.verdictTone` round-trips as a raw string (Foundation-only
/// DTO, see JISnapshot); this maps it back to `JICore.VerdictTone` for
/// `JIColor.color(for:)`. Unknown/future values fall back to `.muted`
/// rather than crashing the extension.
func verdictTone(from raw: String) -> VerdictTone {
    switch raw {
    case "go": .go
    case "amber": .amber
    case "red": .red
    default: .muted
    }
}

private struct VerdictActivityLockScreenView: View {
    let state: VerdictActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(JIColor.color(for: verdictTone(from: state.verdictTone)))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.verdictWord)
                    .font(.headline)
                    .foregroundStyle(JIColor.text)
                Text(state.verdictSession)
                    .font(.caption)
                    .foregroundStyle(JIColor.muted)
            }
            Spacer()
            if let readiness = state.readiness {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(readiness.rounded()))")
                        .font(.title2.bold())
                        .foregroundStyle(JIColor.text)
                    Text("readiness")
                        .font(.caption2)
                        .foregroundStyle(JIColor.muted)
                }
            }
        }
        .padding()
    }
}

#Preview("Lock Screen", as: .content, using: VerdictActivityAttributes()) {
    VerdictLiveActivity()
} contentStates: {
    VerdictActivityAttributes.ContentState(
        verdictWord: "GO",
        verdictSession: "full session",
        verdictTone: "go",
        readiness: 78,
        lastUpdate: .now
    )
    VerdictActivityAttributes.ContentState(
        verdictWord: "REDUCED",
        verdictSession: "session",
        verdictTone: "amber",
        readiness: 52,
        lastUpdate: .now
    )
}
