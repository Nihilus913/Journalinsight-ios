import SwiftUI

/// W-GUI F7 — report §4.5 "one fixed height per family": the nested tile (level-2 recipe:
/// opaque fill, 8 % highlight, 5 % rim, radius 18, no material) at its family's height. Macro
/// tiles, fact tiles, stat cards and "also watching" tiles are all `JITile`s; their content is
/// pinned top-leading and truncates — a tile never grows (DEV-06). `tint` is the one hero tile
/// per row at most (report §4.1 tinted variant).
public struct JITile<Content: View>: View {
    private let family: JITileHeight, tint: Color?, padding: CGFloat, content: Content

    public init(family: JITileHeight = .tile, tint: Color? = nil, padding: CGFloat = JISpacing.tilePadding, @ViewBuilder content: () -> Content) {
        self.family = family; self.tint = tint; self.padding = padding; self.content = content()
    }

    public var body: some View {
        Surface(level: 2, padding: padding, tint: tint) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .jiTileHeight(family)
    }
}

/// The dashed "add" tile of the same family height (Edit Today "Add a square", Goals "Add").
public struct JIAddTile: View {
    private let family: JITileHeight, label: String, action: () -> Void
    @Environment(\.jiTheme) private var theme

    public init(family: JITileHeight = .tile, label: String = "Add", action: @escaping () -> Void) {
        self.family = family; self.label = label; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: JISpacing.s1) {
                Image(systemName: "plus").font(.title3.weight(.semibold))
                Text(label).jiFont(.footnote, weight: .semibold).lineLimit(1)
            }
            .foregroundStyle(theme.color(.info))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous)
                .strokeBorder(theme.color(.mutedNested), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous))
            .jiTileHeight(family)
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel(label)
    }
}
