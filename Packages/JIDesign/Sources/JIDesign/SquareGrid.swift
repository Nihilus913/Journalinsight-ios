import SwiftUI

/// B-57 §1: the badge on a square. `hide` = "−" (edit mode on Today/Recovery), `selected` = "✓"
/// (catalogue: already on Today), `add` = "+" (catalogue / hidden).
public nonisolated enum JISquareBadge: Sendable, Equatable { case none, hide, selected, add }

public nonisolated struct JISquareItem: Identifiable, Sendable, Equatable {
    public let id: String, label: String, systemImage: String?
    public let tint: JIColorRole
    public let value: Double?, decimals: Int, unit: String?, goalText: String?
    public let status: JISignalStatus?
    public let badge: JISquareBadge
    public init(id: String, label: String, systemImage: String? = nil, tint: JIColorRole = .text, value: Double?,
                decimals: Int = 0, unit: String? = nil, goalText: String? = nil, status: JISignalStatus? = nil,
                badge: JISquareBadge = .none) {
        self.id = id; self.label = label; self.systemImage = systemImage; self.tint = tint; self.value = value
        self.decimals = decimals; self.unit = unit; self.goalText = goalText; self.status = status; self.badge = badge
    }
}

/// Drag-to-reorder: `moving` lands directly before `target`. Unknown ids / self-drop = unchanged.
public nonisolated func squareGridMove(_ ids: [String], moving: String, before target: String) -> [String] {
    guard moving != target, ids.contains(moving), ids.contains(target) else { return ids }
    var out = ids.filter { $0 != moving }
    let at = out.firstIndex(of: target) ?? out.endIndex
    out.insert(moving, at: at)
    return out
}

/// W-GUI F7 (DEV-06): which fixed-height family a grid's squares belong to — Today / Recovery
/// squares are `.square` (172), the Edit Today / My KPIs catalogue is `.catalogSquare` (104).
/// Every cell in a grid gets the family's height; text truncates, never grows the cell.
public nonisolated func squareTileFamily(catalog: Bool) -> JITileHeight { catalog ? .catalogSquare : .square }

/// Three squares a row; two at accessibility sizes so a label never truncates to nothing.
public nonisolated func squareGridColumnCount(isAccessibilitySize: Bool) -> Int { isAccessibilitySize ? 2 : 3 }
/// A screen may ask for fewer columns (Recovery's board = 2); AX sizes still cap it at 2.
public nonisolated func squareGridColumnCount(preferred: Int, isAccessibilitySize: Bool) -> Int {
    max(1, min(preferred, squareGridColumnCount(isAccessibilitySize: isAccessibilitySize)))
}

/// W-FIX3 BUG-33 (R4-09): at AX sizes the icon goes above the label, so the label gets the
/// square's full width and a word like "Resting" wraps whole instead of hyphenating.
public nonisolated func squareLabelStacksIcon(isAccessibilitySize: Bool) -> Bool { isAccessibilitySize }

/// W-FIX3 BUG-33 (R1-19): the badge glyph is half its circle, and the circle is a `@ScaledMetric`,
/// so the "−" / "✓" / "+" never overflows the badge at AX3.
public nonisolated func squareBadgeGlyphPointSize(side: CGFloat) -> CGFloat { side / 2 }
/// The badge circle follows the type size between 24 and 32 pt — a corner badge, never a disc
/// that covers the square's icon at AX sizes.
public nonisolated func squareBadgeSide(scaled: CGFloat) -> CGFloat { min(max(scaled, 24), 32) }

/// W-FIX4 BUG-19 (EditToday − badge): where the badge lives relative to the square's drag source.
public nonisolated enum JISquareBadgeHost: Sendable, Equatable { case insideSquare, aboveDragSource }
/// Always above: inside `.draggable` + `.contentShape(Rectangle())` (the editing branch) the drag
/// interaction and the clipped hit shape swallowed the "−" tap, so it never removed a square.
public nonisolated func squareBadgeHost(editing: Bool, draggable: Bool) -> JISquareBadgeHost { .aboveDragSource }
/// The badge's hit target: the drawn circle, grown to the 44-pt HIG minimum around its centre.
public nonisolated func squareBadgeHitSide(side: CGFloat) -> CGFloat { max(side, 44) }

public nonisolated func squareAccessibilityLabel(_ item: JISquareItem) -> String {
    var parts = [item.label]
    if let v = item.value {
        var value = jiGroupedNumber(v, item.decimals)
        if let unit = item.unit, !unit.isEmpty { value += " \(unit)" }
        if let goal = item.goalText { value += " \(goal)" }
        parts.append(value)
    } else {
        parts.append("no value")
    }
    if let status = item.status { parts.append(status.word) }
    return parts.joined(separator: ", ")
}

public nonisolated func squareBadgeActionLabel(_ item: JISquareItem) -> String? {
    switch item.badge {
    case .none: nil
    case .hide: "Hide \(item.label)"
    case .add: "Add \(item.label)"
    case .selected: "Remove \(item.label) from Today"
    }
}

public struct SquareGrid: View {
    let items: [JISquareItem], editing: Bool, columns: Int
    /// W-GUI F7: the fixed-height family of every cell (DEV-06).
    let family: JITileHeight
    let onTap: ((String) -> Void)?, onBadge: ((String) -> Void)?, onMove: ((String, String) -> Void)?, onAdd: (() -> Void)?
    /// False = the dashed "Add" square still closes the grid (board) but is inert — nothing to add.
    let canAdd: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(items: [JISquareItem], editing: Bool = false, columns: Int = 3, family: JITileHeight = .square,
                onTap: ((String) -> Void)? = nil, onBadge: ((String) -> Void)? = nil,
                onMove: ((String, String) -> Void)? = nil, onAdd: (() -> Void)? = nil, canAdd: Bool = true) {
        self.items = items; self.editing = editing; self.columns = columns; self.family = family
        self.onTap = onTap; self.onBadge = onBadge; self.onMove = onMove; self.onAdd = onAdd
        self.canAdd = canAdd
    }

    public var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: JISpacing.cardGap, alignment: .top),
                            count: squareGridColumnCount(preferred: columns, isAccessibilitySize: typeSize.isAccessibilitySize))
        LazyVGrid(columns: columns, spacing: JISpacing.cardGap) {
            ForEach(items) { item in
                square(item)
            }
            if editing, let onAdd {
                AddSquare(action: onAdd, enabled: canAdd, family: family)
            }
        }
    }

    @ViewBuilder
    private func square(_ item: JISquareItem) -> some View {
        let ids = items.map(\.id)
        let base = MetricSquare(item: item, family: family)
            .contentShape(Rectangle())
            .onTapGesture { if !editing { onTap?(item.id) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(squareAccessibilityLabel(item))
            .accessibilityAddTraits(onTap != nil && !editing ? .isButton : [])
            .accessibilityIdentifier("square.\(item.id)")
        if editing, let onMove {
            base
            #if !os(watchOS)
                .draggable(item.id)
                .dropDestination(for: String.self) { dropped, _ in
                    guard let moving = dropped.first else { return false }
                    onMove(moving, item.id); return true
                }
            #endif
                .accessibilityAction(named: "Move earlier") {
                    if let i = ids.firstIndex(of: item.id), i > 0 { onMove(item.id, ids[i - 1]) }
                }
                .accessibilityAction(named: "Move later") {
                    if let i = ids.firstIndex(of: item.id), i + 2 < ids.count { onMove(item.id, ids[i + 2]) }
                    else if let i = ids.firstIndex(of: item.id), i + 1 < ids.count, let last = ids.last { onMove(last, item.id) }
                }
                .modifier(BadgeAction(item: item, onBadge: onBadge))
                .overlay(alignment: .topLeading) { SquareBadge(item: item, onBadge: onBadge) }
        } else {
            base.modifier(BadgeAction(item: item, onBadge: onBadge))
                .overlay(alignment: .topLeading) { SquareBadge(item: item, onBadge: onBadge) }
        }
    }
}

private struct BadgeAction: ViewModifier {
    let item: JISquareItem, onBadge: ((String) -> Void)?
    func body(content: Content) -> some View {
        if let label = squareBadgeActionLabel(item), let onBadge {
            content.accessibilityAction(named: label) { onBadge(item.id) }
        } else {
            content
        }
    }
}

/// One square: icon + label pinned top, the value (or "—") in the middle, the goal fraction and
/// the worded status at the bottom. W-GUI F7 (DEV-06): a FIXED family height — text truncates
/// and shrinks, never grows the cell, so every square in a row is the same size.
struct MetricSquare: View {
    let item: JISquareItem
    var family: JITileHeight = .square
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let labelLayout = squareLabelStacksIcon(isAccessibilitySize: typeSize.isAccessibilitySize)
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
            labelLayout {
                if let symbol = item.systemImage { Image(systemName: symbol).accessibilityHidden(true) }
                Text(item.label).lineLimit(2).minimumScaleFactor(0.7)
            }
            .jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(item.value == nil ? .muted : item.tint))
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(item.value.map { $0.isFinite ? jiGroupedNumber($0, item.decimals) : "—" } ?? "—")
                    .jiNumeral(.numeralCompact, tint: item.value == nil ? .muted : item.tint)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if item.value != nil, let unit = item.unit, !unit.isEmpty {
                    Text(unit).jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
            }
            // W-FIX1 BUG-05: the caption ("as of Sep 21", goal) gets its own line so it never squeezes the number.
            if let goal = item.goalText {
                // RG-50: two lines so "goal 75.0 · as of 19 Sep" is not truncated to "as of 1…".
                Text(goal).jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let status = item.status {
                Label(status.word, systemImage: status.symbolName)
                    .jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(status.role))
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .padding(JISpacing.tilePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color(.surface), in: RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous))
        .jiTileHeight(family)
    }
}

/// The square's corner badge ("−" / "✓" / "+"), hosted by `SquareGrid` above the drag source
/// (W-FIX4 BUG-19). The circle straddles the top-leading corner as before; the hit target is the
/// circle grown to 44 pt around its centre, so the whole drawn badge is tappable.
struct SquareBadge: View {
    let item: JISquareItem
    let onBadge: ((String) -> Void)?
    @Environment(\.jiTheme) private var theme
    @ScaledMetric(relativeTo: .caption) private var scaledBadge: CGFloat = 24
    private var badgeSide: CGFloat { squareBadgeSide(scaled: scaledBadge) }

    var body: some View {
        // No badge = no hit target: a bare square's corner stays the square's own tap.
        if item.badge != .none {
            let hit = squareBadgeHitSide(side: badgeSide)
            // Centre of the drawn circle sits at (side/2 − side/3) from the corner, as before.
            let centre = badgeSide / 2 - badgeSide / 3
            badge.offset(x: centre - hit / 2, y: centre - hit / 2)
        }
    }

    @ViewBuilder private var badge: some View {
        switch item.badge {
        case .none: EmptyView()
        case .hide: badgeButton("minus", fill: .control, tint: .text)
        case .selected: badgeButton("checkmark", fill: .go, tint: .bg)
        case .add: badgeButton("plus", fill: .info, tint: .bg)
        }
    }

    private func badgeButton(_ symbol: String, fill: JIColorRole, tint: JIColorRole) -> some View {
        Button { onBadge?(item.id) } label: {
            Circle().fill(theme.color(fill)).frame(width: badgeSide, height: badgeSide)
                .overlay {
                    Image(systemName: symbol).font(.system(size: squareBadgeGlyphPointSize(side: badgeSide), weight: .bold))
                        .foregroundStyle(theme.color(tint))
                }
                .frame(width: squareBadgeHitSide(side: badgeSide), height: squareBadgeHitSide(side: badgeSide))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressableScale)
        .disabled(onBadge == nil)
        .accessibilityHidden(true)   // exposed as a named action on the square instead
        .accessibilityIdentifier("square.\(item.id).badge")
    }
}

/// W-GUI T7 (mockup 15): the dashed square's visible label.
public nonisolated let addSquareLabel = "Add a square"

/// The dashed "Add" square that closes an editing grid.
struct AddSquare: View {
    let action: () -> Void
    var enabled = true
    var family: JITileHeight = .square
    @Environment(\.jiTheme) private var theme
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.title2)
                Text(addSquareLabel).jiFont(.footnote, weight: .semibold).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            .foregroundStyle(theme.color(.info))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous)
                .strokeBorder(theme.color(.mutedNested), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .jiTileHeight(family)
        }
        .buttonStyle(.pressableScale)
        .disabled(!enabled)
        .accessibilityLabel("Add a square")
        .accessibilityHint(enabled ? "" : "Every square is already on Today")
        .accessibilityIdentifier("square.add")
    }
}
