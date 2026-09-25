import SwiftUI
import Observation
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// W-FIX2 BUG-31: the personalization accent every selection / CTA / link (`JIColorRole.info`)
/// renders in. Green by default (the boards; `AccentKey.emerald`). The app root writes the user's
/// Appearance accent here; `@Observable`, so every body that resolved `.info` redraws on a change.
/// Metric colours never read it (HRV has its own `.hrv`).
@Observable @MainActor
public final class JIAccent {
    public static let shared = JIAccent()

    /// The system green: the default accent and the fallback before the app root has loaded prefs.
    public nonisolated static var defaultColor: Color {
        #if os(iOS) || os(tvOS) || os(visionOS)
        Color(uiColor: .systemGreen)
        #elseif os(macOS)
        Color(nsColor: .systemGreen)
        #else
        .green
        #endif
    }

    public var color: Color = JIAccent.defaultColor

    private init() {}
}

/// W-FIX2 BUG-16: the screens are drawn in a layer BEHIND the chrome-only `TabView`
/// (RootTabView / `TabTransition`), so the floating tab bar is never part of their safe area and
/// the last control of a scroll came to rest under the bar. This is the bar's height above the
/// home-indicator inset the layer already has; on a regular width the bar is a sidebar (0).
public nonisolated func tabBarBottomClearance(_ width: JIWidthClass) -> CGFloat {
    width == .regular ? 0 : 56
}
