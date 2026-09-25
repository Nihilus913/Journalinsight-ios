import SwiftUI

/// B-33 §8.0: which visual language a screen renders in. Phase C (2026-09-22) deleted the
/// RN-era `.classic` language, so `.native` (the iOS 27 system-semantic one) is the only case
/// left and the environment default. The enum stays so the `~40 .jiTheme(.native)` call sites,
/// `ScreenRegistry` entries and the app root keep reading as an explicit opt-in.
/// `nonisolated`: pure value (JIDesign is MainActor by default).
public nonisolated enum JITheme: String, Sendable, CaseIterable, Codable, Equatable {
    case native
}

public extension EnvironmentValues {
    /// The active theme. Always `.native` since Phase C — see `docs/THEME_STATUS.md` (HT).
    @Entry var jiTheme: JITheme = .native
}

public extension View {
    /// Opt a screen (or any subtree) into a theme. Every JIDesign view reads `\.jiTheme`.
    func jiTheme(_ theme: JITheme) -> some View { environment(\.jiTheme, theme) }
}

public extension EnvironmentValues {
    /// Whether the rings / arc play their 0 → value reveal on appear. Default `true` (the app).
    /// `false` renders the FINAL value immediately, with no animation: what a snapshot harness
    /// needs, because an off-screen render captures the frame before the reveal has run and every
    /// ring comes out empty (B-33 phase-B verifier F1).
    @Entry var jiRevealAnimations: Bool = true
}

public extension View {
    /// Turn the reveal animations off (snapshot / sweep renders) or back on for a subtree.
    func jiRevealAnimations(_ on: Bool) -> some View { environment(\.jiRevealAnimations, on) }
}

/// Every neutral / semantic colour a screen may ask for. The ONLY way to name a colour since
/// Phase C: there are no colour statics left to reach for.
public nonisolated enum JIColorRole: Sendable, CaseIterable, Equatable {
    case bg, surface, surface2, surface3, nested, control
    case text, muted, mutedNested
    case hairlineOuter, hairlineNested
    /// Reserved: verdict / band / 0–100 score / status ONLY (rule 6). Selection + CTA = info.
    case go, reduced, danger, info, sleep
    /// B-57 W1 r5: the four macro colours the Monitor / Plan boards tint nutrition figures with
    /// (Calories orange, Protein pink, Carbs yellow, Fat light blue). Metric colours only —
    /// never a verdict, so calories are not "Modified" even though both read orange.
    case kcal, protein, carbs, fat
}

public nonisolated extension JIColorRole {
    /// The macro roles, in the boards' table order (Calories, Protein, Carbs, Fat).
    static let macroRoles: [JIColorRole] = [.kcal, .protein, .carbs, .fat]
}

public extension JITheme {
    /// MainActor (reads the platform's semantic colours): call from `body` or a `@MainActor` test.
    func color(_ role: JIColorRole) -> Color {
        switch self {
        case .native: JINativePalette.color(role)
        }
    }
}

public nonisolated enum JIRadiusRole: Sendable, CaseIterable, Equatable { case hero, card, nested, control }

public nonisolated extension JITheme {
    /// §2: native hero = card = 26, nested 18 (concentric 26 − 8 padding), control 12.
    func radius(_ role: JIRadiusRole) -> CGFloat {
        switch role {
        case .hero, .card: 26
        case .nested: 18
        case .control: 12
        }
    }
}

/// `Surface(level:)` → fill role + radius role. Any unknown level falls back to the card
/// surface (CONTEXT §7). `theme` is kept in the signature: the mapping is a theme concern and
/// every call site already has one to hand.
public nonisolated func surfaceStyle(level: Int, theme: JITheme) -> (fill: JIColorRole, radius: JIRadiusRole) {
    switch level {
    case 2: (.surface2, .nested)
    case 3: (.control, .control)
    default: (.surface, .card)
    }
}
