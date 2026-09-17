import JICore
import JIDesign
import JISnapshot
import SwiftUI
import WidgetKit

/// The App-Group suite `SnapshotStore` reads from. Must match
/// `com.apple.security.application-groups` in `Widgets/Widgets.entitlements`
/// and `App/JournalInsight.entitlements` (L0, frozen this wave).
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

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 4) {
                Circle()
                    .fill(JIColor.color(for: verdictTone(from: snapshot.verdictTone)))
                    .frame(width: 10, height: 10)
                Text(snapshot.verdictWord)
                    .font(.headline)
                    .foregroundStyle(JIColor.text)
                    .lineLimit(1)
                Text(snapshot.verdictSession)
                    .font(.caption2)
                    .foregroundStyle(JIColor.muted)
                    .lineLimit(1)
            }
            .containerBackground(JIColor.bg, for: .widget)
        } else {
            // Never render a zero/blank for missing data (CLAUDE.md rule 5) —
            // an honest "no data yet" state instead.
            VStack(alignment: .leading, spacing: 4) {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(JIColor.muted)
            }
            .containerBackground(JIColor.bg, for: .widget)
        }
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
