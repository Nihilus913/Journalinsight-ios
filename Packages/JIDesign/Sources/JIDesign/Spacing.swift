import SwiftUI

/// W-GUI F1 — report §4.5: the spacing scale (4 · 8 · 12 · 16 · 24 · 32 and nothing else) and
/// the layout constants derived from it. `--s1…--s8` in the 2026-09-25 mockups.
/// `nonisolated`: pure values (JIDesign's default isolation is MainActor).
public nonisolated enum JISpacing {
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s6: CGFloat = 24
    public static let s8: CGFloat = 32
    /// Between cards, and between squares in a card-level grid.
    public static let cardGap: CGFloat = s3
    /// Between nested tiles inside a card.
    public static let tileGap: CGFloat = s2
    /// All surface levels; grouped-list cards use 6/16 (rows carry their own 12).
    public static let cardPadding: CGFloat = s4
    /// Nested tile padding.
    public static let tilePadding: CGFloat = s3
    /// Every screen: cards and tiles span 402 − 32 = 370 pt.
    public static let sideMargin: CGFloat = s4
}

/// W-GUI F1 — report §4.5 tile-height families: ONE fixed height per family; text truncates,
/// never grows the tile (DEV-06). `base` is the value at the default content size category;
/// `.jiTileHeight(_:)` scales a family together with `@ScaledMetric(relativeTo: .body)`.
public nonisolated enum JITileHeight: Sendable, CaseIterable, Equatable {
    /// Today square (metric grid).
    case square
    /// Generic nested tile (also-watching, tile rows).
    case tile
    /// Edit Today / My KPIs catalogue square.
    case catalogSquare
    /// Stat card (KPI detail top row).
    case statCard
    /// Fact tile (Recovery three-up).
    case factTile
    /// Macro tile (Day nutrition row).
    case macroTile
    /// Inset grouped row minimum.
    case row
    /// Primary / secondary button.
    case button
    /// Glass round button (44 × 44).
    case glassButton

    public var base: CGFloat {
        switch self {
        case .square: 172
        case .tile: 96
        case .catalogSquare: 104
        case .statCard: 120
        case .factTile: 64
        case .macroTile: 96
        case .row: 56
        case .button: 52
        case .glassButton: 44
        }
    }
}

/// Applies a tile family's height, scaled with Dynamic Type off `.body` so every tile of a
/// family in a row grows together and stays equal (DEV-06).
public struct JIScaledTileModifier: ViewModifier {
    @ScaledMetric private var height: CGFloat
    public init(family: JITileHeight) {
        _height = ScaledMetric(wrappedValue: family.base, relativeTo: .body)
    }
    public func body(content: Content) -> some View {
        content.frame(height: height)
    }
}

public extension View {
    /// `.jiTileHeight(.square)` — the family's fixed, Dynamic-Type-scaled height.
    func jiTileHeight(_ family: JITileHeight) -> some View { modifier(JIScaledTileModifier(family: family)) }
}
