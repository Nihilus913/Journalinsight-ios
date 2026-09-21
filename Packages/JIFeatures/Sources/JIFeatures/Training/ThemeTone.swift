import SwiftUI
import JICore
import JIDesign

/// B-33: the theme-aware counterpart of `JIColor.color(for:)` (JIDesign is consume-only this
/// wave, so the mapping lives here). Same tone → role mapping, resolved through the active
/// theme so a native screen gets `systemGreen`/`systemOrange`/`systemRed` instead of the RN hexes.
func trainingToneColor(_ tone: VerdictTone, _ theme: JITheme) -> Color {
    switch tone {
    case .go: theme.color(.go)
    case .amber: theme.color(.reduced)
    case .red: theme.color(.danger)
    case .muted: theme.color(.muted)
    }
}
