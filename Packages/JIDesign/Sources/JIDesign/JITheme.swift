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
