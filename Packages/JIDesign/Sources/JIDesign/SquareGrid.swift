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

/// Three squares a row; two at accessibility sizes so a label never truncates to nothing.
public nonisolated func squareGridColumnCount(isAccessibilitySize: Bool) -> Int { isAccessibilitySize ? 2 : 3 }
/// A screen may ask for fewer columns (Recovery's board = 2); AX sizes still cap it at 2.
public nonisolated func squareGridColumnCount(preferred: Int, isAccessibilitySize: Bool) -> Int {
    max(1, min(preferred, squareGridColumnCount(isAccessibilitySize: isAccessibilitySize)))
}

public nonisolated func squareAccessibilityLabel(_ item: JISquareItem) -> String {
    var parts = [item.label]
    if let v = item.value {
        var value = jiNumber(v, item.decimals)
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
    let onTap: ((String) -> Void)?, onBadge: ((String) -> Void)?, onMove: ((String, String) -> Void)?, onAdd: (() -> Void)?
    /// False = the dashed "Add" square still closes the grid (board) but is inert — nothing to add.
    let canAdd: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(items: [JISquareItem], editing: Bool = false, columns: Int = 3, onTap: ((String) -> Void)? = nil, onBadge: ((String) -> Void)? = nil,
                onMove: ((String, String) -> Void)? = nil, onAdd: (() -> Void)? = nil, canAdd: Bool = true) {
        self.items = items; self.editing = editing; self.columns = columns; self.onTap = onTap; self.onBadge = onBadge; self.onMove = onMove; self.onAdd = onAdd
        self.canAdd = canAdd
    }

    public var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                            count: squareGridColumnCount(preferred: columns, isAccessibilitySize: typeSize.isAccessibilitySize))
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { item in
                square(item)
            }
            if editing, let onAdd {
                AddSquare(action: onAdd, enabled: canAdd)
            }
        }
    }

    @ViewBuilder
    private func square(_ item: JISquareItem) -> some View {
        let ids = items.map(\.id)
        let base = MetricSquare(item: item, onBadge: onBadge)
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
        } else {
            base.modifier(BadgeAction(item: item, onBadge: onBadge))
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

/// One square: icon + label, the value (or "—"), the goal fraction, and the worded status.
struct MetricSquare: View {
    let item: JISquareItem
    let onBadge: ((String) -> Void)?
    @Environment(\.jiTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var minSide: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let symbol = item.systemImage { Image(systemName: symbol).accessibilityHidden(true) }
                Text(item.label).lineLimit(2).minimumScaleFactor(0.8)
            }
            .jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(item.value == nil ? .muted : item.tint))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(jiValueText(item.value, decimals: item.decimals))
                    .jiNumeral(.numeralCompact, tint: item.value == nil ? .muted : item.tint)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if item.value != nil, let unit = item.unit, !unit.isEmpty {
                    Text(unit).jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
            }
            // W-FIX1 BUG-05: the caption ("as of Sep 21", goal) gets its own line so it never squeezes the number.
            if let goal = item.goalText {
                Text(goal).jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let status = item.status {
                Label(status.word, systemImage: status.symbolName)
                    .jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(status.role))
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minSide, alignment: .topLeading)
        .background(theme.color(.surface), in: RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous))
        .overlay(alignment: .topLeading) { badge.offset(x: -8, y: -8) }
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
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(theme.color(tint))
                .frame(width: 24, height: 24).background(theme.color(fill), in: Circle())
        }
        .buttonStyle(.pressableScale)
        .disabled(onBadge == nil)
        .accessibilityHidden(true)   // exposed as a named action on the square instead
    }
}

/// The dashed "Add" square that closes an editing grid.
struct AddSquare: View {
    let action: () -> Void
    var enabled = true
    @Environment(\.jiTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var minSide: CGFloat = 104
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.title2)
                Text("Add").jiFont(.footnote, weight: .semibold)
            }
            .foregroundStyle(theme.color(.info))
            .frame(maxWidth: .infinity, minHeight: minSide)
            .overlay(RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous)
                .strokeBorder(theme.color(.mutedNested), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
        .buttonStyle(.pressableScale)
        .disabled(!enabled)
        .accessibilityLabel("Add a square")
        .accessibilityHint(enabled ? "" : "Every square is already on Today")
        .accessibilityIdentifier("square.add")
    }
}
