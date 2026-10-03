import ActivityKit
import JICore
import JIDesign
import SwiftUI
import WidgetKit

/// W-B38-B B-7 — lock screen + Dynamic Island for the strength session mirrored from the Watch:
/// exercise, set n/N, kg × reps, the rest countdown (`Text(timerInterval:)` — the system ticks it,
/// no per-second updates) and HR against the user's own limit. Reads only `context.state`.
struct StrengthSessionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StrengthSessionActivityAttributes.self) { context in
            StrengthSessionLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(widgetTheme.color(.bg))
                .activitySystemActionForegroundColor(widgetTheme.color(.text))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(context.state.setLine.uppercased()).font(.caption2.bold()).foregroundStyle(widgetTheme.color(.muted))
                        Text(context.state.exercise).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(widgetTheme.color(.text))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StrengthHRView(state: context.state, large: false)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let load = context.state.loadLine { Text(load).font(.title3.bold()).foregroundStyle(widgetTheme.color(.text)) }
                        Spacer()
                        StrengthRestView(state: context.state)
                    }
                }
            } compactLeading: {
                Label(context.state.setLine, systemImage: "dumbbell.fill").font(.caption2.bold()).lineLimit(1)
                    .foregroundStyle(widgetTheme.color(.text))
            } compactTrailing: {
                if let end = context.state.restEndsAt, let start = context.state.restStartedAt, end > .now {
                    Text(timerInterval: start...end, countsDown: true).monospacedDigit().font(.caption2)
                        .frame(maxWidth: 44).foregroundStyle(widgetTheme.color(.info))
                } else if let hr = context.state.hrBpm {
                    Text("\(hr)").font(.caption2.bold()).foregroundStyle(strengthBandColor(context.state.capBand))
                }
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(strengthBandColor(context.state.capBand))
            }
        }
    }
}

/// The band's colour; the band is always ALSO named in words (never colour alone).
@MainActor func strengthBandColor(_ band: StrengthSessionActivityState.CapBand) -> Color {
    switch band {
    case .unknown, .noLimit: widgetTheme.color(.muted)
    case .under: widgetTheme.color(.go)
    case .approaching: widgetTheme.color(.reduced)
    case .breach: widgetTheme.color(.danger)
    }
}

nonisolated func strengthBandWord(_ band: StrengthSessionActivityState.CapBand) -> String {
    switch band {
    case .unknown: "No reading"
    case .noLimit: "No limit"
    case .under: "Under limit"
    case .approaching: "Near limit"
    case .breach: "Over limit"
    }
}

private struct StrengthHRView: View {
    let state: StrengthSessionActivityState
    let large: Bool
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Image(systemName: "heart.fill").font(.caption2)
                Text(state.hrBpm.map(String.init) ?? "—").font(large ? .title2.bold() : .title3.bold()).monospacedDigit()
                if let limit = state.limitBpm { Text("/ \(limit)").font(.caption2).foregroundStyle(widgetTheme.color(.muted)) }
            }
            .foregroundStyle(strengthBandColor(state.capBand))
            Text(strengthBandWord(state.capBand)).font(.caption2.bold()).foregroundStyle(strengthBandColor(state.capBand))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StrengthRestView: View {
    let state: StrengthSessionActivityState
    var body: some View {
        if let end = state.restEndsAt, let start = state.restStartedAt, end > .now {
            HStack(spacing: 4) {
                Text("Rest").font(.caption.bold()).foregroundStyle(widgetTheme.color(.muted))
                Text(timerInterval: start...end, countsDown: true).monospacedDigit().font(.title3.bold())
                    .foregroundStyle(widgetTheme.color(.info))
            }
        }
    }
}

private struct StrengthSessionLockScreenView: View {
    let attributes: StrengthSessionActivityAttributes
    let state: StrengthSessionActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(attributes.title.uppercased()).font(.caption2.bold()).foregroundStyle(widgetTheme.color(.muted))
                        Text(timerInterval: attributes.startedAt...Date.distantFuture, countsDown: false)
                            .monospacedDigit().font(.caption2).foregroundStyle(widgetTheme.color(.muted))
                    }
                    Text(state.exercise).font(.headline).lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(widgetTheme.color(.text))
                    HStack(spacing: 8) {
                        Text(state.setLine).font(.subheadline.bold()).foregroundStyle(widgetTheme.color(.text))
                        if let load = state.loadLine { Text(load).font(.subheadline).foregroundStyle(widgetTheme.color(.text)) }
                    }
                }
                Spacer(minLength: 8)
                StrengthHRView(state: state, large: true)
            }
            StrengthRestView(state: state)
        }
        .padding()
    }
}

#Preview("Strength · resting", as: .content, using: StrengthSessionActivityAttributes(startedAt: .now.addingTimeInterval(-900))) {
    StrengthSessionActivityWidget()
} contentStates: {
    StrengthSessionActivityState(exercise: "Barbell Bench Press", setNumber: 2, setCount: 4, weightKg: 52.5, reps: 8,
                                 restStartedAt: .now, restEndsAt: .now.addingTimeInterval(90), hrBpm: 152, limitBpm: 175,
                                 capBand: .under, updatedAt: .now)
    StrengthSessionActivityState(exercise: "Plank", setNumber: 1, setCount: 3, durationS: 45, hrBpm: nil, limitBpm: 175,
                                 capBand: .unknown, updatedAt: .now)
}
