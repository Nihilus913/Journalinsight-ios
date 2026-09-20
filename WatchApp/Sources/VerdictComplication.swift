import SwiftUI
import WidgetKit
import JIDesign
import JISnapshot

/// A single complication face: today's verdict word + tone, nothing else
/// (complications are glance-only real estate).
public nonisolated struct VerdictComplicationEntry: TimelineEntry, Equatable {
    public let date: Date
    public let verdictWord: String
    public let tone: String

    public init(date: Date, verdictWord: String, tone: String) {
        self.date = date
        self.verdictWord = verdictWord
        self.tone = tone
    }
}

/// Pure timeline logic, independent of WidgetKit's provider plumbing so it
/// can be exercised directly: a snapshot in produces an entry carrying that
/// snapshot's verdict; no snapshot (or an unreadable App-Group store)
/// produces a single muted placeholder entry, never a fabricated verdict.
///
/// One entry is enough this wave — the complication has nothing to predict
/// ahead of the next hub fetch, so there's no future timeline to project;
/// `WidgetCenter.reloadTimelines` (called after `SnapshotStore.write`, App
/// side) is what actually refreshes it when a new snapshot lands.
public nonisolated func complicationTimelineEntries(
    from snapshot: HubSnapshot?,
    now: Date = Date()
) -> [VerdictComplicationEntry] {
    guard let snapshot else {
        return [VerdictComplicationEntry(date: now, verdictWord: "—", tone: "muted")]
    }
    return [VerdictComplicationEntry(date: now, verdictWord: snapshot.verdictWord, tone: snapshot.tone(now: now))]
}

private extension HubSnapshot {
    /// Complications are glance-only: a snapshot older than 36h reads as
    /// stale and is shown muted rather than a possibly-wrong go/red color,
    /// even though the word itself is still displayed.
    nonisolated func tone(now: Date) -> String {
        if let lastSync, now.timeIntervalSince(lastSync) > 36 * 3600 { return "muted" }
        return verdictTone
    }
}

public nonisolated struct VerdictComplicationProvider: TimelineProvider {
    private let store: SnapshotStore

    public init(suiteName: String = watchAppGroupSuite) {
        self.store = SnapshotStore(suiteName: suiteName)
    }

    public func placeholder(in context: Context) -> VerdictComplicationEntry {
        VerdictComplicationEntry(date: Date(), verdictWord: "GO", tone: "go")
    }

    public func getSnapshot(in context: Context, completion: @escaping (VerdictComplicationEntry) -> Void) {
        completion(complicationTimelineEntries(from: store.read()).first ?? placeholder(in: context))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<VerdictComplicationEntry>) -> Void) {
        let entries = complicationTimelineEntries(from: store.read())
        completion(Timeline(entries: entries, policy: .never))
    }
}

private struct VerdictComplicationView: View {
    let entry: VerdictComplicationEntry

    var body: some View {
        VStack(spacing: 1) {
            Text(entry.verdictWord)
                .jiFont(.footnote, weight: .bold, design: .rounded)   // W9.5-L4: JITypography token (13pt) — no fixed sizes (W8-L3 rule)
                .foregroundStyle(verdictToneColor(entry.tone))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
}

public struct VerdictComplication: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VerdictComplication", provider: VerdictComplicationProvider()) { entry in
            VerdictComplicationView(entry: entry)
        }
        .configurationDisplayName("Verdict")
        .description("Today's training verdict at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
