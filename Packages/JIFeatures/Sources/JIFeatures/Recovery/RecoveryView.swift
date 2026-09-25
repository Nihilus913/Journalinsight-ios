import SwiftUI
import JICore
import JIDesign

/// Recovery screen (frozen contract `RecoveryView.init(model:)`). B-57 W1: the v11 board —
/// "Last night" squares (HRV · Sleep · Resting HR · Load) with Edit / hide / reorder, a
/// "+ Add a metric" entry into the KPI catalogue, and HRV over the last 7 nights. Rule 5 (never
/// render a zero for missing data) applies throughout: a missing square is "— No data".
public struct RecoveryView: View {
    @Bindable private var model: RecoveryViewModel
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: no hub fetch while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen
    @AppStorage("recovery.tileOrder") private var orderRaw = ""
    @AppStorage("recovery.tileHidden") private var hiddenRaw = ""
    @State private var editing = false
    @Environment(\.openKpiCatalogue) private var openKpiCatalogue
    @Environment(\.openKpiDetail) private var openKpiDetail

    public init(model: RecoveryViewModel) { self.model = model }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                    .accessibilityLabel("No data yet — run a sync on the hub.")
                case .loaded: loaded
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        // §5: the hand-drawn large title becomes the system one; the date line is the subtitle.
        .navigationTitle("Recovery")
        .navigationSubtitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .toolbar { ToolbarItem(placement: .primaryAction) { Button(editing ? "Done" : "Edit") { editing.toggle() }.accessibilityIdentifier("recovery.edit") } }
        .refreshable { await model.refresh() }
        // CODE-1: gate on `hasLiveResult`, not `phase == .idle` — mirrors `TodayView.task`.
        .task { if !offscreen, !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var lastNightLabel: some View {
        Text("Last night").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
    }

    private var loading: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(width: 160, height: 160); SkeletonBlock(width: 240); SkeletonBlock(height: 90) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                    .accessibilityLabel(msg)
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("recovery.retry")
            }
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let staleDate = staleVerdictBanner {
                // B-46 item 7: the staleness banner used to hug its text and read narrower
                // than every card under it. `Surface` sizes to its content and is frozen, so the
                // width is asserted here, exactly like `StalenessBanner` already does.
                Surface(level: 2) {
                    Text("Showing recovery from \(staleDate) — no newer sync yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityLabel("Showing recovery from \(staleDate) — no newer sync yet.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("recovery.staleBanner")
            }
            // W-FIX4 PF-04: the one rule, not the fetch time; at AX sizes the pill stacks under
            // "Last night" instead of breaking "Synced" mid-word.
            ViewThatFits(in: .horizontal) {
                HStack { lastNightLabel; Spacer(); OneSyncedPill().fixedSize() }
                VStack(alignment: .leading, spacing: 6) { lastNightLabel; OneSyncedPill().fixedSize(horizontal: false, vertical: true) }
            }
            let layout = recoveryTileLayout(orderRaw: orderRaw, hiddenRaw: hiddenRaw)
            SquareGrid(items: recoveryTileItems(days: model.days, layout: layout, editing: editing), editing: editing, columns: recoveryGridColumns,
                       onTap: openKpiDetail.map { open in { id in open(id == "load" ? "acwr" : id) } },
                       onBadge: { id in hiddenRaw = (layout.hidden + [id]).joined(separator: ",") },
                       onMove: { moving, target in orderRaw = squareGridMove(layout.visible + layout.hidden, moving: moving, before: target).joined(separator: ",") },
                       onAdd: layout.hidden.first.map { first in { hiddenRaw = layout.hidden.filter { $0 != first }.joined(separator: ",") } })
            if let openKpiCatalogue {
                Button { openKpiCatalogue() } label: {
                    Label("Add a metric", systemImage: "plus").jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.info))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .overlay(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                            .strokeBorder(theme.color(.mutedNested), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                }
                .buttonStyle(.pressableScale)
                .accessibilityIdentifier("recovery.addMetric")
            }
            HStack(alignment: .firstTextBaseline) {
                Text("HRV, last 7 nights").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
                Spacer()
            }
            Surface(level: 1) {
                NormalBarChart(points: recoveryHrvNights(days: model.days), normal: nil, unit: "ms")
                    .accessibilityIdentifier("recovery.hrvChart")
            }
        }
    }

    private var staleVerdictBanner: String? {
        if case .staleVerdictDate(let date) = model.screenState { return date }
        return nil
    }
}

/// The hub's `YYYY-MM-DD` day string as a chart x-value. UTC on purpose — a day string has no
/// time zone, and `TrendChart` only ever orders and labels these.
public nonisolated func recoveryTrendDate(_ day: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
    var c = calendar
    c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return c.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}
