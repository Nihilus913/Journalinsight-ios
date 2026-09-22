import JICore
import JISnapshot
import WidgetKit

/// W-B34 (B-36): timeline entry for the configurable KPI widget — the snapshot plus the one KPI
/// the user picked in the widget's configuration.
struct KpiEntry: TimelineEntry {
    let date: Date
    let snapshot: HubSnapshot?
    let metric: KpiMetricId
}

/// Reads the same App-Group `HubSnapshot` as `SnapshotTimelineProvider` — no network access from
/// the extension. `.never`: the app writes a fresh snapshot after each fetch and calls
/// `WidgetCenter.shared.reloadAllTimelines()` (App/AppEnvironment.swift, W-B34 L1).
struct KpiTimelineProvider: AppIntentTimelineProvider {
    let store: SnapshotStore

    init(store: SnapshotStore = SnapshotStore(suiteName: WidgetAppGroup.suiteName)) {
        self.store = store
    }

    func placeholder(in context: Context) -> KpiEntry {
        KpiEntry(date: .now, snapshot: .previewSeed, metric: .readiness)
    }

    func snapshot(for configuration: SelectKpiIntent, in context: Context) async -> KpiEntry {
        KpiEntry(date: .now,
                 snapshot: context.isPreview ? .previewSeed : store.read(),
                 metric: configuration.metric)
    }

    func timeline(for configuration: SelectKpiIntent, in context: Context) async -> Timeline<KpiEntry> {
        let entry = KpiEntry(date: .now, snapshot: store.read(), metric: configuration.metric)
        return Timeline(entries: [entry], policy: .never)
    }
}
