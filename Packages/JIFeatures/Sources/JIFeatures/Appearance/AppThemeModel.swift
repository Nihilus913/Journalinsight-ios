import Foundation
import Observation
import SwiftUI
import JIDesign
import JIPersistence
#if canImport(UIKit)
import UIKit
#endif

/// W-FIX2 BUG-15 (P-appearance): what the app ROOT applies — the persisted `ThemePrefs` mode,
/// accent and text size. The root used to hard-code `.preferredColorScheme(.dark)`, so the app was
/// always dark and an Appearance choice only reached the open Settings sheet.
/// It re-reads the store whenever `ThemePrefsStore.save` posts `didChange` (the Appearance screen
/// builds its own `AppearanceViewModel` on the same `PrefStore`), and loads on init, so the
/// choice survives a relaunch.
@Observable @MainActor
public final class AppThemeModel {
    public private(set) var prefs: ThemePrefs

    @ObservationIgnored private let store: PrefStore
    @ObservationIgnored private let applyAccent: (Color) -> Void
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    /// `applyAccent` defaults to the design system's shared accent (`JIAccent`), which every
    /// `JIColorRole.info` resolves to; tests inject a recorder instead of mutating the singleton.
    public init(prefs store: PrefStore, applyAccent: @escaping (Color) -> Void = { JIAccent.shared.color = $0 }) {
        self.store = store
        self.applyAccent = applyAccent
        self.prefs = ThemePrefsStore.load(from: store)
        applyAccent(prefs.accentKey.nativeColor)
        observer = NotificationCenter.default.addObserver(forName: ThemePrefsStore.didChange, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public var mode: ThemeMode { prefs.mode }
    public var accentKey: AccentKey { prefs.accentKey }
    /// nil = follow the device.
    public var preferredColorScheme: ColorScheme? { prefs.mode.preferredColorScheme }
    public var accent: Color { prefs.accentKey.nativeColor }
    /// The range the root clamps Dynamic Type to: one fixed size, or the whole range for "Auto".
    public var dynamicTypeRange: ClosedRange<DynamicTypeSize> {
        prefs.fontScalePreset.dynamicTypeSize.map { $0...$0 } ?? DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5
    }

    public func reload() {
        let next = ThemePrefsStore.load(from: store)
        if next.accentKey != prefs.accentKey { applyAccent(next.accentKey.nativeColor) }
        if next != prefs { prefs = next }
    }
}

#if canImport(UIKit)
public nonisolated extension ThemeMode {
    /// The window override the root sets. SwiftUI's `.preferredColorScheme(nil)` does not reliably
    /// hand a window back to the system once it was forced, so the root sets this on every window.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self { case .system: .unspecified; case .light: .light; case .dark: .dark }
    }
}

@MainActor
public extension AppThemeModel {
    /// Applies the mode to every window of the app (sheets included — they share the window).
    func applyToWindows() {
        let style = prefs.mode.userInterfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
#endif
