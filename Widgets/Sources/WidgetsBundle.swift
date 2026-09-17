import WidgetKit
import SwiftUI

/// Placeholder widget bundle for the JournalInsight widget + Live Activity
/// extension. L3 (P-widgets, P-live-activity) fills in GateWidget, KpiWidget
/// and VerdictLiveActivity this wave; this file only keeps the extension
/// target buildable until then.
@main
struct WidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

private struct PlaceholderWidget: Widget {
    let kind: String = "PlaceholderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { entry in
            Text("JournalInsight")
        }
        .configurationDisplayName("JournalInsight")
        .description("Placeholder — replaced by GateWidget/KpiWidget in L3.")
    }
}

private struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

private struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: Date())], policy: .never))
    }
}
