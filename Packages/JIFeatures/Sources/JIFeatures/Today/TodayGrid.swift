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
// MARK: W9.5-L4 (P-today) — rotation: width-driven columns

/// W9.5-L4: the minimum tile width the grid's `.adaptive` columns fit. Compact width (every
/// iPhone in portrait, non-Max iPhones in landscape) keeps the RN oracle's 2-up on a portrait
/// phone (≈370pt usable → 2 tiles) yet lets an 18 Pro landscape (≈720pt usable) fill 4;
/// regular width (iPad, Max landscape) grows the tile so a 10" pane doesn't shatter into 6 —
/// B-33 §8.5 caps that growth at 160 so the four summary tiles still make one row inside the
/// 720 pt `readableColumn()` at 956 pt — 680 pt of content after the 20 pt gutters (200 left
/// them 3-up with a widow on the next row).
public nonisolated func todayGridMinimumTileWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
    switch horizontalSizeClass {
    case .regular: 160
    default: 150
    }
}

/// W9.5-L4: the `LazyVGrid` columns for the tile grid — one `.adaptive(minimum:)` item (the
/// `GateRespondCard.swift` override-chip pattern) so rotation re-flows the count instead of
/// stretching 2 fixed columns across a landscape width.
public nonisolated func todayGridColumns(horizontalSizeClass: UserInterfaceSizeClass?) -> [GridItem] {
    [GridItem(.adaptive(minimum: todayGridMinimumTileWidth(horizontalSizeClass: horizontalSizeClass)), spacing: todayGridSpacing)]
}

/// Inter-tile spacing shared by the columns and the rows.
public nonisolated let todayGridSpacing: CGFloat = 12

/// W9.5-L4: how many tiles `.adaptive(minimum:)` fits in `availableWidth` — the same arithmetic
/// SwiftUI's adaptive layout runs (`n` tiles + `n−1` gaps), floored at 1 so a width narrower than
/// one tile still lays out. Pure, so the rotation contract is unit-testable without a window.
public nonisolated func todayGridColumnCount(availableWidth: CGFloat, minimumTileWidth: CGFloat, spacing: CGFloat = todayGridSpacing) -> Int {
    guard minimumTileWidth > 0 else { return 1 }
    return max(1, Int(((availableWidth + spacing) / (minimumTileWidth + spacing)).rounded(.down)))
}

public nonisolated func dataFreshnessBadgeTapAction(onOpenDataQuality: @escaping () -> Void) -> () -> Void {
    { onOpenDataQuality() }
}

/// Story 1: the full Today tile grid — the four `TodayViewModel.chips` (fixed default order
/// hrv, rhr, sleep, steps) as `StatChip`s, plus the energy-availability `EAGatedTile` (not
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
    @State private var isReordering = false
    @State private var draggingID: String?
    @State private var showMind = false
    @State private var showDataQuality = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// W9.5-L4 (P-today): rotation — the size class picks the minimum tile width; the column
    /// count then follows the available width (2 portrait phone, 3+ landscape / iPad).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.jiTheme) private var theme

    /// B-33 §8.1: the bespoke `LazyVGrid`/rotation maths is JIDesign's `Columns` now; the pure
    /// `todayGridMinimumTileWidth` seam (and its tests) stays as the size-class floor it feeds.
    private var tileMinimum: CGFloat { todayGridMinimumTileWidth(horizontalSizeClass: horizontalSizeClass) }

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
        VStack(alignment: .leading, spacing: 16) {
            DataFreshnessBadge(info: freshness, onTap: dataFreshnessBadgeTapAction(onOpenDataQuality: { showDataQuality = true }))
            Columns(minimum: tileMinimum, spacing: todayGridSpacing) {
                ForEach(orderedChips) { chip in
                    tile(for: chip)
                }
            }
            .jiHapticCue(.selection, on: order, when: { _ in draggingID != nil })   // W8-L1 (P-haptics) — oracle DraggableTodayTiles.tsx:179 hapticSelection() on each live swap mid-drag
            .jiHapticCue(.dragDrop, on: draggingID, when: { $0 == nil })         // W8-L1 (P-haptics) — oracle DraggableTodayTiles.tsx:193 hapticDragDrop() when the finger lifts and commits
            EAGatedTile(label: "Energy availability")
                .accessibilityLabel("Energy availability")
                .accessibilityIdentifier("today.tile.energyAvailability")
            mindTile
        }
        .onAppear { order = loadTileOrder(prefs: prefs, chipIDs: chips.map(\.id)) }
        .onChange(of: chips.map(\.id)) { _, ids in order = resolveTileOrder(chipIDs: ids, savedOrder: order.isEmpty ? nil : order) }
        .navigationDestination(isPresented: $showMind) {
            if let makeMindViewModel { MindView(model: makeMindViewModel()) }
        }
        .navigationDestination(isPresented: $showDataQuality) {
            if let model = makeDataQualityViewModel() { DataQualityView(model: model) } else { DataQualityUnavailableView() }
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
        StatChip(label: chip.label, value: chip.value, unit: chip.unit, points: chip.points, sourceMissing: chip.sourceMissing, action: chipTapAction(id: chip.id, onSelectKpi: onSelectKpi))
            // Label is the RN oracle's StatChip default (`${label} — open detail`), verbatim.
            .accessibilityLabel("\(chip.label) — open detail")
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
                saveTileOrder(order, prefs: prefs)
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
