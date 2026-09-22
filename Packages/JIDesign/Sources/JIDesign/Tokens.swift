import SwiftUI
import JICore

/// tokens.ts `ThemeScheme` — which neutral ramp the app's light/dark switch resolves to. The
/// hex ramps themselves are gone (B-33 Phase C deleted `JIPalette`/`JIColor`); this stays
/// because `ThemePrefs.ThemeMode.resolvedScheme(system:)` is still the port of
/// ThemeProvider.tsx's mode → scheme resolution. `nonisolated`: pure value (JIDesign's default
/// isolation is MainActor).
public nonisolated enum JIScheme: String, Sendable, CaseIterable, Codable, Equatable {
    case dark, light
}
