import ActivityKit
import JICore
import JIDesign
import JISnapshot
import SwiftUI
import WidgetKit

/// Lock-screen / Dynamic Island presentation for `VerdictActivityAttributes`.
/// Reads only `context.state` — never touches `SnapshotStore` directly, so
/// it has no App-Group or Keychain dependency beyond what `LiveActivityController`
/// already fed it.
struct VerdictLiveActivity: Widget {
    private let theme = widgetTheme

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VerdictActivityAttributes.self) { context in
            VerdictActivityLockScreenView(state: context.state)
                .activityBackgroundTint(theme.color(.bg))
                .activitySystemActionForegroundColor(theme.color(.text))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("YOUR CALL").font(.caption2.bold())
                        Text(context.state.verdictWord).font(.title.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .foregroundStyle(tone(context.state.verdictTone))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let hrv = context.state.signals?.first(where: { $0.key == "hrv" }) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("OVERNIGHT HRV").font(.caption2.bold()).foregroundStyle(theme.color(.muted))
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(hrv.valueText).font(.title3.bold()).foregroundStyle(theme.color(widgetSignalRole(hrv)))
                                if hrv.value != nil { Text(hrv.unit).font(.caption2).foregroundStyle(theme.color(.muted)) }
                            }
                            Text(hrv.word == "Low" ? "↓ \(hrv.word)" : hrv.word).font(.caption2.bold())
                                .foregroundStyle(theme.color(widgetSignalRole(hrv)))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        glanceSessionText(context.state.verdictSession).font(.headline).foregroundStyle(theme.color(.text)).lineLimit(glanceSessionLineLimit(context.state.verdictSession))
                        if let reason = context.state.reason {
                            Text(reason).font(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Label(context.state.verdictWord, systemImage: "dumbbell.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(tone(context.state.verdictTone))
                    .lineLimit(1)
            } compactTrailing: {
                // Toby 2026-09-24: the cap only when the user set one, else the next session, else nothing.
                if let cap = context.state.hrCap {
                    Text("cap \(cap)").font(.caption2).foregroundStyle(theme.color(.danger))
                } else if let next = context.state.nextSession?.components(separatedBy: " · ").first, !next.isEmpty {
                    Text("next \(next)").font(.caption2).foregroundStyle(theme.color(.muted))
                }
            } minimal: {
                Circle().fill(tone(context.state.verdictTone)).frame(width: 8, height: 8)
            }
        }
    }

    private func tone(_ raw: String) -> Color {
        widgetToneColor(verdictTone(from: raw))
    }
}

/// `HubSnapshot.verdictTone` round-trips as a raw string (Foundation-only
/// DTO, see JISnapshot); this maps it back to `JICore.VerdictTone` for
/// `widgetToneColor(_:)`. Unknown/future values fall back to `.muted`
/// rather than crashing the extension.
func verdictTone(from raw: String) -> VerdictTone {
    switch raw {
    case "go": .go
    case "amber": .amber
    case "red": .red
    default: .muted
    }
}

/// B-57 W5 (board 6/13): YOUR CALL + word + session + "Why", and on the right HRV, the user's
/// cap (only when set — else the next session) and RHR, each with its word, never colour alone.
private struct VerdictActivityLockScreenView: View {
    let state: VerdictActivityAttributes.ContentState
    private let theme = widgetTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR CALL").font(.caption2.bold()).foregroundStyle(widgetToneColor(verdictTone(from: state.verdictTone)))
                Text(state.verdictWord).font(.largeTitle.weight(.heavy)).foregroundStyle(widgetToneColor(verdictTone(from: state.verdictTone)))
                    .lineLimit(1).minimumScaleFactor(0.5)
                glanceSessionText(state.verdictSession).font(.headline).foregroundStyle(theme.color(.text)).lineLimit(glanceSessionLineLimit(state.verdictSession))
                if let reason = state.reason { Text("Why: \(reason)").font(.caption).foregroundStyle(theme.color(.muted)).lineLimit(2) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let hrv = state.signals?.first(where: { $0.key == "hrv" }) {
                    row(hrv.label, hrv.valueText, hrv.value == nil ? nil : hrv.unit, hrv.word, widgetSignalRole(hrv))
                }
                if let cap = state.hrCap {
                    row("Cap", "\(cap)", "bpm", "Yours", .danger)
                } else if let next = state.nextSession {
                    // Toby 2026-09-24: no cap ⇒ this slot shows the next session.
                    row("Next", next.components(separatedBy: " · ").first ?? next, nil, "Plan", .info)
                }
                if let rhr = state.signals?.first(where: { $0.key == "rhr" }) {
                    row("RHR", rhr.valueText, rhr.value == nil ? nil : rhr.unit, rhr.word, widgetSignalRole(rhr))
                }
            }
        }
        .padding()
    }

    private func row(_ label: String, _ value: String, _ unit: String?, _ word: String, _ role: JIColorRole) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(theme.color(.muted))
            Text(value).font(.title3.bold()).foregroundStyle(theme.color(role))
            if let unit { Text(unit).font(.caption2).foregroundStyle(theme.color(.muted)) }
            Text(word).font(.caption.bold()).foregroundStyle(theme.color(role))
        }
        .accessibilityElement(children: .combine)
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
        lastUpdate: .now,
        reason: "HRV under your 27–30, night 1 of 2",
        hrCap: 175,   // canvas only: a user who set a cap
        nextSession: "Fri · Day 3 Full Upper",
        signals: HubSnapshot.previewSeed.signals
    )
    VerdictActivityAttributes.ContentState(
        verdictWord: "REDUCED",
        verdictSession: "session",
        verdictTone: "amber",
        readiness: 52,
        lastUpdate: .now,
        reason: "HRV under your 27–30, night 1 of 2",
        hrCap: nil,   // the no-cap face: the slot shows the next session
        nextSession: "Fri · Day 3 Full Upper",
        signals: HubSnapshot.previewSeed.signals
    )
}

/// W-FIX7 F7-1: the app writes "Done · Traditional strength · 52 min · Bevel" as the session once
/// Apple Health holds a matching workout today — the glances show it with a check and room for
/// two lines (type · duration · source app), never truncated to "Done · Tradit…".
nonisolated func glanceSessionIsDone(_ session: String) -> Bool { session.hasPrefix("Done · ") }

func glanceSessionText(_ session: String) -> Text {
    guard glanceSessionIsDone(session) else { return Text(session) }
    return Text("\(Image(systemName: "checkmark.circle.fill")) \(session)")
}

nonisolated func glanceSessionLineLimit(_ session: String) -> Int { glanceSessionIsDone(session) ? 2 : 1 }
