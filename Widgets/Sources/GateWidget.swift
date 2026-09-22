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
        // The extension never polls the hub itself — App/AppEnvironment.swift (W2c-L1)
        // writes a fresh snapshot after each fetch and reloads our timelines via
        // WidgetCenter; .never here means "wait to be told", not "stale forever".
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
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

    /// §4b / §8.4: one bounded value per family. Readiness (0–100) is the only bounded number the
    /// snapshot carries, so the circular accessory is a `ScoreRing` and the small/medium tiles
    /// lead with the fade arc; the rectangular accessory has no room for art and stays text.
    /// No family is added (§8.3 keeps `systemLarge` out until iPad is on).
    @ViewBuilder private var content: some View {
        if let snapshot {
            switch family {
            case .accessoryCircular:
                if let readiness = snapshot.readiness {
                    ScoreRing(value: readiness, max: 100,
                              tint: widgetToneColor(verdictTone(from: snapshot.verdictTone)), size: 36)
                } else {
                    noData
                }
            case .accessoryRectangular:
                verdictLines(snapshot)
            case .systemSmall:
                VStack(spacing: 6) {
                    if let readiness = snapshot.readiness {
                        ReadinessArcGauge(score: readiness, size: 78)
                    }
                    verdictLines(snapshot)
                }
            default:
                HStack(spacing: 12) {
                    if let readiness = snapshot.readiness {
                        ReadinessArcGauge(score: readiness, size: 92)
                    }
                    verdictLines(snapshot)
                    Spacer(minLength: 0)
                }
            }
        } else {
            // Never render a zero/blank for missing data (CLAUDE.md rule 5) —
            // an honest "no data yet" state instead.
            noData
        }
    }

    private func verdictLines(_ snapshot: HubSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.verdictWord)
                .jiFont(.subheadline, weight: .bold)
                .foregroundStyle(widgetToneColor(verdictTone(from: snapshot.verdictTone)))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(snapshot.verdictSession)
                .jiFont(.micro)
                .foregroundStyle(theme.color(.muted))
                .lineLimit(1)
        }
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
        fetchedAt: .now,
        lastSync: .now
    )
}

#Preview("Gate — small", as: .systemSmall, widget: { GateWidget() }, timeline: {
    SnapshotEntry(date: .now, snapshot: .previewSeed)
    SnapshotEntry(date: .now, snapshot: nil)
})
