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

    @State private var order: [String] = []
    @State private var isReordering = false
    @State private var draggingID: String?
    @State private var showMind = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    public init(
        chips: [TodayChip], prefs: PrefStore?, onSelectKpi: @escaping (String) -> Void,
        mindTodayCheckin: CheckIn? = nil, makeMindViewModel: (() -> MindViewModel)? = nil
    ) {
        self.chips = chips
        self.prefs = prefs
        self.onSelectKpi = onSelectKpi
        self.mindTodayCheckin = mindTodayCheckin
        self.makeMindViewModel = makeMindViewModel
    }

    private var byID: [String: TodayChip] { Dictionary(uniqueKeysWithValues: chips.map { ($0.id, $0) }) }
    private var orderedChips: [TodayChip] { order.compactMap { byID[$0] } }
    private var jiggling: Bool { jiggleEnabled(isReordering: isReordering, reduceMotion: reduceMotion) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(orderedChips) { chip in
                    tile(for: chip)
                }
            }
            EAGatedTile(label: "Energy availability")
            mindTile
        }
        .onAppear { order = loadTileOrder(prefs: prefs, chipIDs: chips.map(\.id)) }
        .onChange(of: chips.map(\.id)) { _, ids in order = resolveTileOrder(chipIDs: ids, savedOrder: order.isEmpty ? nil : order) }
        .navigationDestination(isPresented: $showMind) {
            if let makeMindViewModel { MindView(model: makeMindViewModel()) }
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
                        Text("MIND").font(.caption.bold()).foregroundStyle(JIColor.mutedNested)
                        if let checkin = mindTodayCheckin {
                            Text("Checked in · stress \(checkin.stress)/5 · energy \(checkin.energy)/5")
                                .font(.footnote).foregroundStyle(JIColor.text)
                        } else {
                            Text("How are you today?").font(.subheadline.bold()).foregroundStyle(JIColor.text)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(JIColor.mutedNested)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mindTodayCheckin != nil ? "Today's mind check-in — update" : "How are you today — daily check-in")
    }

    @ViewBuilder
    private func tile(for chip: TodayChip) -> some View {
        StatChip(label: chip.label, value: chip.value, unit: chip.unit, points: chip.points, sourceMissing: chip.sourceMissing, action: chipTapAction(id: chip.id, onSelectKpi: onSelectKpi))
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
