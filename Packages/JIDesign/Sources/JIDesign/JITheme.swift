import SwiftUI

/// B-33 §8.0: which visual language a screen renders in. `.classic` = the RN-era tokens (every
/// existing screen, the app-root default); `.native` = the iOS 27 system-semantic language.
/// A screen opts in with `.jiTheme(.native)` on its root view; sheets inherit their presenter's
/// value unless they set their own. `nonisolated`: pure value (JIDesign is MainActor by default).
public nonisolated enum JITheme: String, Sendable, CaseIterable, Codable, Equatable {
    case classic, native
}

public extension EnvironmentValues {
    /// The active theme. Default `.classic` — see `docs/THEME_STATUS.md` (HT) for who is native.
    @Entry var jiTheme: JITheme = .classic
}

public extension View {
    /// Opt a screen (or any subtree) into a theme. Every JIDesign view reads `\.jiTheme`.
    func jiTheme(_ theme: JITheme) -> some View { environment(\.jiTheme, theme) }
}

/// Every neutral / semantic colour a screen may ask for. Mirrors the `JIColor` statics one to one
/// so a migration is a rename (`JIColor.muted` → `theme.color(.muted)`).
public nonisolated enum JIColorRole: Sendable, CaseIterable, Equatable {
    case bg, surface, surface2, surface3, nested, control
    case text, muted, mutedNested
    case hairlineOuter, hairlineNested
    /// Reserved: verdict / band / 0–100 score / status ONLY (rule 6). Selection + CTA = info.
    case go, reduced, danger, info, sleep
}

public extension JITheme {
    /// MainActor (reads the `JIColor` statics): call from `body` or a `@MainActor` test.
    func color(_ role: JIColorRole) -> Color {
        switch self {
        case .classic: JIColor.classic(role)
        case .native: JINativePalette.color(role)
        }
    }
}
