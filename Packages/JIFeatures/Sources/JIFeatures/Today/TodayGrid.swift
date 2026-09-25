import SwiftUI
import JICore
import JIDesign
import JIPersistence

/// Persisted-preference key for the Today tile order (`[String]` of `TodayChip.id`).
public nonisolated let todayTileOrderKey = "today.tileOrder"

/// Pure order-merge: keeps a persisted order for ids that still exist, appends any new/unknown
/// ids (in the caller's default order) at the end, and falls back to `chipIDs` untouched when
/// nothing has been persisted yet. Never drops a live chip id, never invents one.
public nonisolated func resolveTileOrder(chipIDs: [String], savedOrder: [String]?) -> [String] {
    guard let savedOrder else { return chipIDs }
    let known = Set(chipIDs)
    let kept = savedOrder.filter { known.contains($0) }
    let missing = chipIDs.filter { !kept.contains($0) }
    return kept + missing
}

/// Reads the persisted tile order (if any) and resolves it against the live chip set. `prefs`
/// is optional so a `TodayViewModel` constructed without one (no persistence wired yet) still
/// renders a stable default order instead of crashing.
public nonisolated func loadTileOrder(prefs: PrefStore?, chipIDs: [String]) -> [String] {
    let saved = (try? prefs?.get(todayTileOrderKey, as: [String].self)) ?? nil
    return resolveTileOrder(chipIDs: chipIDs, savedOrder: saved)
}

/// Persists `order`. Silently no-ops when `prefs` is nil or the write fails — losing the
/// remembered order is a minor feel regression, never a crash.
public nonisolated func saveTileOrder(_ order: [String], prefs: PrefStore?) {
    try? prefs?.set(todayTileOrderKey, order)
}

/// W-FIX2 BUG-19: the ids Today's grid shows = EditToday's "On Today" (`visibleTodayTileOrder`),
/// in EditToday's order, limited to the chips this grid was handed (never an invented square).
/// A chip the registry does not know is appended rather than dropped.
public nonisolated func todayGridShownIDs(chipIDs: [String], prefs: TodayTilePrefs) -> [String] {
    let available = Set(chipIDs)
    let known = Set(prefs.order)
    return visibleTodayTileOrder(prefs).filter { available.contains($0) } + chipIDs.filter { !known.contains($0) }
}

/// W-FIX2 BUG-19: folds a Today drag (the shown order) back into the full prefs — hidden squares
/// keep their slots and stay hidden, visible squares this grid did not show keep theirs.
public nonisolated func todayGridCommitOrder(_ prefs: TodayTilePrefs, shownOrder: [String]) -> TodayTilePrefs {
    let visible = visibleTodayTileOrder(prefs)
    let visibleSet = Set(visible)
    let moved = shownOrder.filter { visibleSet.contains($0) }
    let movedSet = Set(moved)
    guard movedSet.count == moved.count else { return prefs }
    var next = moved.makeIterator()
    let newVisible = visible.map { movedSet.contains($0) ? (next.next() ?? $0) : $0 }
    return reorderTodayTiles(prefs, newVisibleOrder: newVisible)
}

/// Whether the reorder jiggle should currently animate. Reduce Motion suppresses it
/// unconditionally (rule 4/7 — no scale/jiggle while Reduce Motion is on); a no-op/opacity-only
/// resting state is used instead.
public nonisolated func jiggleEnabled(isReordering: Bool, reduceMotion: Bool) -> Bool {
    isReordering && !reduceMotion
}

/// Wires a chip tap to `onSelectKpi(id)`. A separate, pure seam so the wiring itself is testable
/// without driving an actual SwiftUI `Button` tap.
public nonisolated func chipTapAction(id: String, onSelectKpi: @escaping (String) -> Void) -> () -> Void {
    { onSelectKpi(id) }
}

/// W4-L2: wires the Mind tile's tap to opening the Mind screen. Same pure-seam pattern as
/// `chipTapAction` above — testable without a SwiftUI test harness.
public nonisolated func mindTileTapAction(onOpenMind: @escaping () -> Void) -> () -> Void {
    { onOpenMind() }
}

/// W5b-L1 (P-data-quality): wires the freshness badge's tap to opening the Data Quality screen
/// (oracle `DataFreshnessBadge.tsx:33`, `router.push("/data-quality")`). Same pure-seam pattern.
// MARK: W-B47 L2 (P-today) — Apple Fitness's 2-up card grid

/// Inter-tile spacing shared by the columns and the rows. 12 pt is what the Fitness Summary
/// reference measures between its two half-width cards (`docs/design/references/
/// 2026-09-22-apple-fitness-summary.png`: cards at x≈16 and x≈207 of a 402 pt screen).
public nonisolated let todayGridSpacing: CGFloat = 12

/// W-B47 Contract: the KPI tiles are Fitness-style `SummaryCard`s **two-up at compact width,
/// three-up at regular** — a deliberate replacement of W9.5-L4's width-driven `.adaptive`
/// columns, which let a landscape phone shatter the row into 4 narrow chips. An accessibility
/// Dynamic Type size drops the grid to one column instead: a 20 pt card title at AX5 cannot
/// share a 393 pt screen with a neighbour without truncating, and B-33 §8.1 is "reflows, never
/// clips". Pure, so the whole contract is unit-testable without a window.
public nonisolated func todayCardColumnCount(horizontalSizeClass: UserInterfaceSizeClass?,
                                             isAccessibilitySize: Bool) -> Int {
    if isAccessibilitySize { return 1 }
    return horizontalSizeClass == .regular ? 3 : 2
}

/// The `LazyVGrid` columns for the card grid — equal-width `.flexible()` items so the two cards
/// are exactly half the content width each (Fitness), never re-flowed by their content.
/// `.top` alignment: a card with an as-of line is taller than its neighbour, and the default
/// centre alignment would offset the shorter one.
public nonisolated func todayCardGridColumns(horizontalSizeClass: UserInterfaceSizeClass?,
                                             isAccessibilitySize: Bool) -> [GridItem] {
    let count = todayCardColumnCount(horizontalSizeClass: horizontalSizeClass, isAccessibilitySize: isAccessibilitySize)
    return Array(repeating: GridItem(.flexible(), spacing: todayGridSpacing, alignment: .top), count: count)
}

public nonisolated func dataFreshnessBadgeTapAction(onOpenDataQuality: @escaping () -> Void) -> () -> Void {
    { onOpenDataQuality() }
}

/// Story 1: the full Today tile grid — the chips it is handed (W-FIX2 BUG-19: `TodayViewModel.squareChips`,
/// filtered and ordered by EditToday's prefs via `todayGridShownIDs`) as summary cards, plus the energy-availability `EAGatedTile` (not
/// computable from the current source — rule 5's gated idiom, not a bare zero). B-7: no
/// `DriverBars` here — the RN oracle (mobile/app/(tabs)/index.tsx) has no driver bars on Today,
/// and repeating hrv/rhr/sleep/steps there duplicated the chips above. `DriverBars` (JIDesign)
/// stays for Recovery.
///
/// Story 2: long-press begins drag-reorder; the new order persists as `[String]` chip ids under
/// `PrefStore` key `today.tileOrder` and is restored on the next load via `loadTileOrder`.
public struct TodayGrid: View {
    let chips: [TodayChip]
    let prefs: PrefStore?
    let onSelectKpi: (String) -> Void
    /// W4-L2 (P-mind): today's check-in, for the tile's summary line — data-only, no store
    /// dependency, matching how `chips` is already passed in. Optional/defaulted so this stays
    /// source-compatible with `TodayView.swift`'s existing call site (not owned by this lane).
    let mindTodayCheckin: CheckIn?
    /// W4-L2: builds the `MindViewModel` the tile pushes to. A factory (not a stored VM) since
    /// `TodayGrid` itself doesn't own persistence wiring — the caller supplies one once it has a
    /// `MindStore` trio to build with. `nil` (the default) renders the tile but wires no
    /// navigation, which is what every current call site gets until integration supplies one.
    let makeMindViewModel: (() -> MindViewModel)?
    /// W5b-L1 (P-data-quality): what the freshness badge line knows (sync time, tracked/total
    /// days). Optional/defaulted like `mindTodayCheckin` so `TodayView.swift`'s call site stays
    /// source-compatible; nil renders the neutral "Data quality" label.
    let freshness: DataFreshnessInfo?
    /// W5b-L1: builds the `DataQualityViewModel` the badge pushes to. Defaults to the
    /// `DataQualityAccess` seam (the app installs the live provider there at boot), so the tap
    /// works without a `TodayView` change; a nil result renders the badge without a tap target.
    let makeDataQualityViewModel: () -> DataQualityViewModel?

    @State private var order: [String] = []
    /// W-FIX2 BUG-19: EditToday's prefs (order + hidden), re-read on every appearance so a change
    /// made in Settings → Edit Today shows the moment Today is back on screen.
    @State private var tilePrefs: TodayTilePrefs = .default
    @State private var isReordering = false
    @State private var draggingID: String?
    @State private var showMind = false
    @State private var showDataQuality = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// W9.5-L4 (P-today): rotation — the size class picks the minimum tile width; the column
    /// count then follows the available width (2 portrait phone, 3+ landscape / iPad).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.jiTheme) private var theme

    /// W-B47: an accessibility Dynamic Type size collapses the grid to one column (see
    /// `todayCardColumnCount`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var gridColumns: [GridItem] {
        todayCardGridColumns(horizontalSizeClass: horizontalSizeClass,
                             isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    public init(
        chips: [TodayChip], prefs: PrefStore?, onSelectKpi: @escaping (String) -> Void,
        mindTodayCheckin: CheckIn? = nil, makeMindViewModel: (() -> MindViewModel)? = nil,
        freshness: DataFreshnessInfo? = nil,
        makeDataQualityViewModel: @escaping () -> DataQualityViewModel? = { DataQualityAccess.shared.makeViewModel() }
    ) {
        self.chips = chips
        self.prefs = prefs
        self.onSelectKpi = onSelectKpi
        self.mindTodayCheckin = mindTodayCheckin
        self.makeMindViewModel = makeMindViewModel
        self.freshness = freshness
        self.makeDataQualityViewModel = makeDataQualityViewModel
    }

    private var byID: [String: TodayChip] { Dictionary(uniqueKeysWithValues: chips.map { ($0.id, $0) }) }
    private var orderedChips: [TodayChip] { order.compactMap { byID[$0] } }
    private var jiggling: Bool { jiggleEnabled(isReordering: isReordering, reduceMotion: reduceMotion) }

    public var body: some View {
        // W-FIX3 BUG-28 (board 02): the squares only — no data-quality badge, locked Energy
        // availability tile or Mind row on Day (Data quality lives in Settings, Mind in More).
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: gridColumns, spacing: todayGridSpacing) {
                ForEach(orderedChips) { chip in
                    tile(for: chip)
                }
            }
            .jiHapticCue(.selection, on: order, when: { _ in draggingID != nil })   // W8-L1 (P-haptics) — oracle DraggableTodayTiles.tsx:179 hapticSelection() on each live swap mid-drag
            .jiHapticCue(.dragDrop, on: draggingID, when: { $0 == nil })         // W8-L1 (P-haptics) — oracle DraggableTodayTiles.tsx:193 hapticDragDrop() when the finger lifts and commits
        }
        .onAppear {
            tilePrefs = loadTodayTilePrefs(prefs: prefs)
            order = todayGridShownIDs(chipIDs: chips.map(\.id), prefs: tilePrefs)
        }
        .onChange(of: chips.map(\.id)) { _, ids in order = todayGridShownIDs(chipIDs: ids, prefs: tilePrefs) }
        // W-FIX3 C-a: a sheet closing over Today (Edit Today, My KPIs) fires no onAppear here — the
        // write itself says so, and the grid re-reads the one selection at once.
        .task {
            for await _ in NotificationCenter.default.notifications(named: todayTilePrefsDidChange) {
                tilePrefs = loadTodayTilePrefs(prefs: prefs)
                order = todayGridShownIDs(chipIDs: chips.map(\.id), prefs: tilePrefs)
            }
        }
    }

    /// E12-17 parity — the daily mind check-in promoted onto Today (oracle `MindTile.tsx`). Tap
    /// opens the Mind screen (`.navigationDestination` above); RN's separate "chevron opens the
    /// full screen without firing the check-in sheet" affordance collapses to one destination
    /// here since this tile doesn't itself present the check-in sheet (that's `MindView`'s job).
    private var mindTile: some View {
        Button(action: mindTileTapAction(onOpenMind: { showMind = true })) {
            Surface(level: 2, padding: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MIND").jiFont(.caption, weight: .bold).foregroundStyle(theme.color(.mutedNested))
                        if let checkin = mindTodayCheckin {
                            Text("Checked in · stress \(checkin.stress)/5 · energy \(checkin.energy)/5")
                                .jiFont(.footnote).foregroundStyle(theme.color(.text))
                        } else {
                            Text("How are you today?").jiFont(.subheadline, weight: .bold).foregroundStyle(theme.color(.text))
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(theme.color(.mutedNested))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mindTodayCheckin != nil ? "Today's mind check-in — update" : "How are you today — daily check-in")
        .accessibilityIdentifier("today.tile.mind")
        .accessibilityHint("Opens the Mind screen")
    }

    @ViewBuilder
    private func tile(for chip: TodayChip) -> some View {
        let spec = todaySummaryCardSpec(for: chip)
        SummaryCard(icon: spec.icon, tint: theme.color(spec.tintRole), title: spec.title,
                    value: spec.value, unit: spec.unit, timestamp: spec.timestamp,
                    sparkline: spec.sparkline, sourceMissing: spec.sourceMissing,
                    action: chipTapAction(id: chip.id, onSelectKpi: onSelectKpi))
            // Label is the RN oracle's StatChip default (`${label} — open detail`), verbatim.
            .accessibilityLabel(chip.asOf.map { "\(chip.label) — open detail, \($0)" } ?? "\(chip.label) — open detail")
            .accessibilityIdentifier("today.chip.\(chip.id)")
            .accessibilityHint("Long-press to reorder the tiles")
            .rotationEffect(.degrees(jiggling ? (chip.id.hashValue % 2 == 0 ? 1.5 : -1.5) : 0))
            .animation(jiggling ? JIMotion.standard.repeatForever(autoreverses: true) : JIMotion.standard, value: jiggling)
            .jiHaptic(.toggleOn, trigger: isReordering)
            .onLongPressGesture(minimumDuration: 0.4) { isReordering = true }
            #if os(iOS)
            .onDrag {
                draggingID = chip.id
                return NSItemProvider(object: chip.id as NSString)
            }
            .onDrop(of: [.text], delegate: TodayTileDropDelegate(item: chip.id, order: $order, draggingID: $draggingID) {
                isReordering = false
                tilePrefs = todayGridCommitOrder(tilePrefs, shownOrder: order)
                saveTodayTilePrefs(tilePrefs, prefs: prefs)
            })
            #endif
    }
}

#if os(iOS)
import UniformTypeIdentifiers

/// Backs the drag-reorder gesture: swaps the dragged tile's id into `item`'s slot as the drag
/// crosses it, and persists (via `onDropped`) once the finger lifts.
struct TodayTileDropDelegate: DropDelegate {
    let item: String
    @Binding var order: [String]
    @Binding var draggingID: String?
    let onDropped: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != item,
              let from = order.firstIndex(of: draggingID), let to = order.firstIndex(of: item) else { return }
        if order[to] != draggingID {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        onDropped()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
#endif


// MARK: - Chip -> Fitness summary card

/// W-B47 L2: everything a Today tile hands `SummaryCard`, as a plain value. `SummaryCard`'s own
/// stored properties are internal to JIDesign (and that file belongs to L1), so this spec — not
/// the view — is the seam a host test can read. It keeps B-46 item 3's guarantee intact: the
/// as-of day the view model computed is provably threaded through to the card's timestamp line.
public nonisolated struct TodaySummaryCardSpec: Equatable, Sendable {
    public let icon: String
    public let tintRole: JIColorRole
    public let title: String
    /// `nil` = no data yet / source missing — `SummaryCard` renders its own muted em dash.
    public let value: String?
    public let unit: String?
    /// B-46 item 3: "as of Sep 15" when the reading is a fallback from an earlier day, else `nil`.
    public let timestamp: String?
    public let sparkline: [Double?]
    public let sourceMissing: Bool
}

/// The SF Symbol per Today KPI — chip ids are `KpiMetricId` raw values. A metric with no bespoke
/// symbol falls back to the neutral chart glyph rather than an invented one.
public nonisolated func todayCardIcon(_ kpiId: String) -> String {
    switch kpiId {
    case "hrv": "waveform.path.ecg"
    case "rhr": "heart.fill"
    case "sleep": "bed.double.fill"
    case "steps": "figure.walk"
    case "body_battery": "battery.75percent"
    case "readiness": "bolt.heart.fill"
    case "acwr": "dumbbell.fill"
    case "weight": "scalemass.fill"
    case "kcal": "flame.fill"
    case "protein", "carbs", "fat": "fork.knife"
    default: "chart.line.uptrend.xyaxis"
    }
}

/// W-B47 INTEGRATE SEAM (one line): L1 lands `metricTintRole(_:)` in `JIDesign/MetricTint.swift`.
/// Until the two lane branches merge, every Today card takes the neutral info tint; integrate
/// replaces this function's single body line with `metricTintRole(kpiId)` and nothing else moves.
public nonisolated func todayCardTintRole(_ kpiId: String) -> JIColorRole {
    metricTintRole(kpiId)
}

/// The card's big numeral, formatted exactly as the `StatChip` it replaces did (whole numbers
/// stay whole, anything else gets one decimal). `nil` when there is nothing to show — rule 5:
/// never a fabricated zero, and never a bare dash with a dangling unit.
public nonisolated func todayCardValueText(_ value: Double?, sourceMissing: Bool) -> String? {
    guard !sourceMissing, let value else { return nil }
    return value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
}

/// B-46 item 3 (fixer), carried forward: the ONE place a `TodayChip` becomes a Today card, so
/// every field the model computes — `asOf` above all — is provably threaded through. The first
/// fix computed "as of Sep 15" in the view model and then dropped it here.
public nonisolated func todaySummaryCardSpec(for chip: TodayChip) -> TodaySummaryCardSpec {
    let value = todayCardValueText(chip.value, sourceMissing: chip.sourceMissing)
    return TodaySummaryCardSpec(
        icon: todayCardIcon(chip.id),
        tintRole: todayCardTintRole(chip.id),
        title: chip.label,
        value: value,
        unit: value == nil ? nil : chip.unit,
        timestamp: chip.sourceMissing ? nil : chip.asOf,
        sparkline: chip.points,
        sourceMissing: chip.sourceMissing
    )
}
