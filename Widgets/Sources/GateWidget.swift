import JICore
import JIDesign
import JISnapshot
import SwiftUI
import WidgetKit

/// The App-Group suite `SnapshotStore` reads from. Must match
/// `com.apple.security.application-groups` in `Widgets/Widgets.entitlements`
/// and `App/JournalInsight.entitlements` (L0, frozen this wave).
/// B-33: widgets ship in the native language. `JIDesign` is consume-only this wave, so the
/// tone → role mapping (the counterpart of the old classic palette lookup) lives here, next to the
/// extension's other shared declarations — a separate file would need a `xcodegen generate` and
/// a `project.pbxproj` diff for one constant.
let widgetTheme = JITheme.native

@MainActor func widgetToneColor(_ tone: VerdictTone) -> Color {
    switch tone {
    case .go: widgetTheme.color(.go)
    case .amber: widgetTheme.color(.reduced)
    case .red: widgetTheme.color(.danger)
    case .muted: widgetTheme.color(.muted)
    }
}

/// B-57 W5: a glance signal's colour role from its word (the word always carries the status too).
func widgetSignalRole(_ s: SnapshotSignal) -> JIColorRole {
    switch s.word {
    case "Low", "High", "Below goal", "Watch": .reduced
    case "Red flag": .danger
    case "No reading": .muted
    default: .info
    }
}

enum WidgetAppGroup {
    static let suiteName = "group.toby913.JournalInsight"
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: HubSnapshot?
}

/// Shared timeline provider: both `GateWidget` and `KpiWidget` read the same
/// `HubSnapshot` from the App Group — no network access from the extension.
struct SnapshotTimelineProvider: TimelineProvider {
    let store: SnapshotStore

    init(store: SnapshotStore = SnapshotStore(suiteName: WidgetAppGroup.suiteName)) {
        self.store = store
    }

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .previewSeed)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .previewSeed : store.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: store.read())
        // The extension never polls the hub itself — App/AppEnvironment.swift writes a fresh
        // snapshot after each fetch (W2c-L1) and, since W-B34, calls
        // `WidgetCenter.shared.reloadAllTimelines()` right after the write; .never here means
        // "wait to be told", not "stale forever".
        completion(Timeline(entries: [entry], policy: .never))
    }
}

/// Home-screen + lock-screen gate widget: today's verdict word/session/tone.
struct GateWidget: Widget {
    let kind = "GateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            GateWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Gate")
        .description("Today's morning verdict.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private struct GateWidgetView: View {
    let snapshot: HubSnapshot?
    @Environment(\.widgetFamily) private var family
    private let theme = widgetTheme

    var body: some View {
        content
            .jiTheme(.native)
            .containerBackground(theme.color(.bg), for: .widget)
    }

    /// B-57 W5 (boards 6/01–05): the call, the reason, plan progress; the arcs are gone — signals
    /// read in words (spec §1 B-33 §4b amendment). A missing value is "—" plus a word, never a number.
    @ViewBuilder private var content: some View {
        if let snapshot {
            let tone = widgetToneColor(verdictTone(from: snapshot.verdictTone))
            switch family {
            case .accessoryCircular:
                // Board 04: the call + sessions done against the plan ("2 of 4 wk").
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "dumbbell.fill").font(.caption2).accessibilityHidden(true)
                        Text(snapshot.verdictWord).jiFont(.caption, weight: .bold).lineLimit(1).minimumScaleFactor(0.5)
                        Text(snapshot.planProgressText.map { "\($0) wk" } ?? "—").jiFont(.micro).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(snapshot.verdictWord), \(snapshot.planProgressText.map { "\($0) sessions this week" } ?? "plan progress unknown")")
            case .accessoryInline:
                // Board 05: "Full · HRV low 1 of 2" — the system adds the date.
                Text(snapshot.inlineGlanceText)
            case .accessoryRectangular:
                // Board 03: the call and the one signal that drove it.
                VStack(alignment: .leading, spacing: 1) {
                    Label(snapshot.verdictWord, systemImage: "dumbbell.fill").jiFont(.subheadline, weight: .bold).lineLimit(1)
                    Text(snapshot.verdictSession).jiFont(.caption, weight: .semibold).lineLimit(1)
                    if let reason = snapshot.reason { Text("Why: \(reason)").jiFont(.caption).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemSmall:
                // Board 01: eyebrow, word, session, the reason.
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow(tone)
                    Text(snapshot.verdictWord).jiNumeral(.numeralLarge, weight: .heavy).foregroundStyle(tone)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(snapshot.verdictSession).jiFont(.caption, weight: .bold).foregroundStyle(theme.color(.text)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let reason = snapshot.reason {
                        Text("Why · \(reason)").jiFont(.micro).foregroundStyle(theme.color(.muted)).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                // Board 02: the call left, each signal against its normal or goal right.
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        eyebrow(tone)
                        Text(snapshot.verdictWord).jiNumeral(.numeralLarge, weight: .heavy).foregroundStyle(tone)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(snapshot.verdictSession).jiFont(.caption, weight: .bold).foregroundStyle(theme.color(.text)).lineLimit(1)
                        Spacer(minLength: 0)
                        if let reason = snapshot.reason {
                            Text("Why: \(reason)").jiFont(.micro).foregroundStyle(theme.color(.muted)).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(snapshot.signals ?? [], id: \.key) { signalColumn($0) }
                    }
                }
            }
        } else {
            // Never render a zero/blank for missing data (CLAUDE.md rule 5) —
            // an honest "no data yet" state instead.
            noData
        }
    }

    private func eyebrow(_ tone: Color) -> some View {
        Text("YOUR CALL").jiFont(.micro, weight: .bold).foregroundStyle(tone)
    }

    /// Value, status word (tinted AND worded) and the normal/goal caption — never colour alone.
    private func signalColumn(_ s: SnapshotSignal) -> some View {
        let role = widgetSignalRole(s)
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(s.valueText).jiNumeral(.numeralSmall).foregroundStyle(theme.color(role))
                if s.value != nil { Text(s.unit).jiFont(.micro).foregroundStyle(theme.color(.muted)) }
            }
            Text(s.word).jiFont(.micro, weight: .bold).foregroundStyle(theme.color(role)).lineLimit(1)
            Text(s.label).jiFont(.micro).foregroundStyle(theme.color(.text)).lineLimit(1)
            Text(s.caption).jiFont(.micro).foregroundStyle(theme.color(.muted)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.label) \(s.valueText) \(s.value == nil ? "" : s.unit), \(s.word), \(s.caption)")
    }

    private var noData: some View {
        Text("No data yet").jiFont(.caption).foregroundStyle(theme.color(.muted))
    }
}

extension HubSnapshot {
    /// Seeded snapshot for widget previews and the `.placeholder` timeline
    /// entry — never shown as real user data, only redacted placeholder UI.
    static let previewSeed = HubSnapshot(
        verdictWord: "GO",
        verdictSession: "full session",
        verdictTone: "go",
        verdictDate: "2026-09-17",
        readiness: 78,
        kpis: [
            SnapshotKPI(label: "RHR", value: 52, unit: "bpm"),
            SnapshotKPI(label: "HRV", value: 61, unit: "ms"),
            SnapshotKPI(label: "Sleep", value: 7.4, unit: "h"),
        ],
        // W-B34: one entry per KPI id, as `publishSnapshot` writes it (nutrition left nil to
        // exercise the "—" face).
        allKpis: KpiMetricId.allCases.map { id in
            let def = KpiMetrics.def(id)
            return SnapshotKPI(id: id, label: def.label, value: previewSeedValues[id], unit: def.unit,
                               normalLow: id == .hrv ? 27 : nil, normalHigh: id == .hrv ? 30 : nil)
        },
        fetchedAt: .now,
        lastSync: .now,
        reason: "HRV under your 27–30, night 1 of 2",
        planDone: 2, planTotal: 4,
        // No cap in the seed: the cap is the user's own input (Toby 2026-09-24) — the placeholder
        // shows the no-cap face ("next Fri"); `previewSeedCapped` is the with-cap canvas only.
        hrCap: nil,
        nextSession: "Fri · Day 3 Full Upper",
        signals: [
            SnapshotSignal(key: "hrv", label: "HRV", value: 25, unit: "ms", normalLow: 27, normalHigh: 30, goal: nil, status: "amber"),
            SnapshotSignal(key: "sleep_h", label: "Sleep", value: 7.4, unit: "h", normalLow: nil, normalHigh: nil, goal: 7, status: "pass"),
            SnapshotSignal(key: "rhr", label: "Resting HR", value: nil, unit: "bpm", normalLow: nil, normalHigh: nil, goal: nil, status: "missing"),
        ]
    )

    /// Canvas-only: the seed as a user who set a cap sees it.
    static var previewSeedCapped: HubSnapshot {
        var s = previewSeed
        s.hrCap = 175
        return s
    }

    private static let previewSeedValues: [KpiMetricId: Double] = [
        .hrv: 25, .rhr: 52, .sleep: 82, .bodyBattery: 64, .readiness: 78,
        .acwr: 1.08, .weight: 93.4, .steps: 8412,
    ]
}

#Preview("Gate — small", as: .systemSmall, widget: { GateWidget() }, timeline: {
    SnapshotEntry(date: .now, snapshot: .previewSeed)
    SnapshotEntry(date: .now, snapshot: nil)
})

#Preview("Gate — medium", as: .systemMedium, widget: { GateWidget() }, timeline: {
    SnapshotEntry(date: .now, snapshot: .previewSeed)
})

#Preview("Gate — rectangular", as: .accessoryRectangular, widget: { GateWidget() }, timeline: {
    SnapshotEntry(date: .now, snapshot: .previewSeed)
})

#Preview("Gate — circular", as: .accessoryCircular, widget: { GateWidget() }, timeline: {
    SnapshotEntry(date: .now, snapshot: .previewSeed)
})

#Preview("Gate — inline", as: .accessoryInline, widget: { GateWidget() }, timeline: {
    SnapshotEntry(date: .now, snapshot: .previewSeed)
    SnapshotEntry(date: .now, snapshot: nil)
})
