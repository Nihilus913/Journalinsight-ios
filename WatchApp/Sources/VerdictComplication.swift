import SwiftUI
import WidgetKit
import JIDesign
import JISnapshot

/// B-57 W5 (boards 6/10–12): the verdict plus the week's plan progress, the HRV comparison and —
/// only when the user set one — the HR cap. Every extra is optional: an old snapshot or a
/// user without a cap never gets an invented number.
public nonisolated struct VerdictComplicationEntry: TimelineEntry, Equatable {
    public let date: Date
    public let verdictWord: String
    public let tone: String
    public let session: String
    public let planText: String?
    public let planFraction: Double?
    /// The user's cap, nil = none (then `capSlot` shows the next session).
    public let hrCap: Int?
    public let nextDay: String?
    public let detail: String?

    public init(date: Date, verdictWord: String, tone: String, session: String = "", planText: String? = nil,
                planFraction: Double? = nil, hrCap: Int? = nil, nextDay: String? = nil, detail: String? = nil) {
        self.date = date
        self.verdictWord = verdictWord
        self.tone = tone
        self.session = session
        self.planText = planText
        self.planFraction = planFraction
        self.hrCap = hrCap
        self.nextDay = nextDay
        self.detail = detail
    }

    /// Same rule as `HubSnapshot.capSlotText`: "cap 175", else "next Fri", else nil.
    public var capSlot: String? { hrCap.map { "cap \($0)" } ?? nextDay.map { "next \($0)" } }
}

/// Board 6/12 inline: "Full · cap 175"; without a cap "Full · next Fri"; else just the word.
public nonisolated func complicationInlineText(_ e: VerdictComplicationEntry) -> String {
    e.capSlot.map { "\(e.verdictWord) · \($0)" } ?? e.verdictWord
}

/// Board 6/11: the HRV comparison when a normal exists ("HRV 25 < 27"), else the reason line.
public nonisolated func complicationRectDetail(_ snapshot: HubSnapshot) -> String? {
    snapshot.signal("hrv")?.compactComparison ?? snapshot.reason
}

/// Pure timeline logic, independent of WidgetKit's provider plumbing so it
/// can be exercised directly: a snapshot in produces an entry carrying that
/// snapshot's verdict; no snapshot (or an unreadable App-Group store)
/// produces a single muted placeholder entry, never a fabricated verdict.
///
/// One entry is enough — the complication has nothing to predict ahead of the next hub fetch;
/// `WidgetCenter.reloadTimelines` (called after `SnapshotStore.write`, App side) refreshes it.
public nonisolated func complicationTimelineEntries(
    from snapshot: HubSnapshot?,
    now: Date = Date()
) -> [VerdictComplicationEntry] {
    guard let snapshot else {
        return [VerdictComplicationEntry(date: now, verdictWord: "—", tone: "muted")]
    }
    return [VerdictComplicationEntry(
        date: now, verdictWord: snapshot.verdictWord, tone: snapshot.tone(now: now), session: snapshot.verdictSession,
        planText: snapshot.planProgressText, planFraction: snapshot.planFraction, hrCap: snapshot.hrCap,
        nextDay: snapshot.nextSessionDay, detail: complicationRectDetail(snapshot)
    )]
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
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Board 10: ring = sessions done against the plan; the call inside. Unknown = "—", empty ring.
            Gauge(value: entry.planFraction ?? 0) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: 0) {
                    Text(entry.verdictWord).jiFont(.footnote, weight: .bold, design: .rounded)
                        .foregroundStyle(verdictToneColor(entry.tone)).minimumScaleFactor(0.5).lineLimit(1)
                    Text(entry.planText ?? "—").jiFont(.micro).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(verdictToneColor(entry.tone))
            .accessibilityLabel("\(entry.verdictWord), \(entry.planText.map { "\($0) sessions" } ?? "plan unknown")")
        case .accessoryInline:
            // Board 12: "Full · cap 175" — or "Full · next Fri" when the user has no cap.
            Text(complicationInlineText(entry))
        default:
            // Board 11: YOUR CALL, word + session, the HRV comparison and the cap (only when set).
            VStack(alignment: .leading, spacing: 1) {
                Label("YOUR CALL", systemImage: "dumbbell.fill").jiFont(.micro, weight: .bold).foregroundStyle(verdictToneColor(entry.tone))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.verdictWord).jiFont(.footnote, weight: .bold, design: .rounded).foregroundStyle(verdictToneColor(entry.tone))
                    Text(entry.session).jiFont(.caption, weight: .semibold).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let detail = entry.detail { Text(detail).jiFont(.caption).foregroundStyle(verdictToneColor("amber")).lineLimit(1) }
                    if let cap = entry.hrCap {
                        Text("cap \(cap)").jiFont(.caption, weight: .semibold).foregroundStyle(verdictToneColor("red"))
                    } else if let next = entry.capSlot {
                        Text(next).jiFont(.caption, weight: .semibold).foregroundStyle(verdictToneColor("muted"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
