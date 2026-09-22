import Foundation
import Observation
import SwiftUI
import JIDesign
import JIPersistence

/// W5a-L1 (P-appearance). The state `mobile/app/appearance.tsx` reads from `useTheme()`
/// (`ThemeProvider.tsx`): the persisted `ThemePrefs` plus the resolved seams (`preferredColorScheme`,
/// `uiAccent`, the greeting preview). Every setter persists immediately through `PrefStore`
/// (RN `update()` → `saveThemePrefs`); the name goes through a draft + `commitName` exactly as RN.
@Observable @MainActor
public final class AppearanceViewModel {
    public private(set) var prefs: ThemePrefs
    /// RN `nameDraft` (TextInput value); committed on blur / submit / Done.
    public var nameDraft: String
    /// Non-nil after a `PrefStore` write failed (rule 5: never silent).
    public private(set) var saveError: String?

    private let store: PrefStore
    private let hour: () -> Int

    /// `hour` is injectable so the greeting preview is testable without `Date()`.
    public init(prefs store: PrefStore, hour: @escaping () -> Int = { Calendar.current.component(.hour, from: Date()) }) {
        self.store = store
        self.hour = hour
        let loaded = ThemePrefsStore.load(from: store)
        self.prefs = loaded
        self.nameDraft = loaded.name
    }

    public var mode: ThemeMode { prefs.mode }
    public var accentKey: AccentKey { prefs.accentKey }
    public var fontScalePreset: FontScalePreset { prefs.fontScalePreset }
    public var name: String { prefs.name }
    public var colorSource: ColorSource { prefs.colorSource }

    /// ThemeProvider.tsx `scheme` → what the app hands `.preferredColorScheme` (nil = system).
    public var preferredColorScheme: ColorScheme? { prefs.mode.preferredColorScheme }
    /// ThemeProvider.tsx `colors.uiAccent` on the fixed rung (iOS has no Material You → always fixed).
    public var uiAccentHex: UInt32 { prefs.accentKey.hex }
    public var uiAccent: Color { prefs.accentKey.color(for: .native) }
    /// nil = Dynamic Type untouched ("Auto").
    public var dynamicTypeSize: DynamicTypeSize? { prefs.fontScalePreset.dynamicTypeSize }

    public func setMode(_ mode: ThemeMode) { update { $0.mode = mode } }
    public func setAccentKey(_ key: AccentKey) { update { $0.accentKey = key } }
    public func setFontScalePreset(_ preset: FontScalePreset) { update { $0.fontScalePreset = preset } }

    /// RN `commitName`: `if (nameDraft.trim() !== name) setName(nameDraft)`.
    public func commitName() {
        let trimmed = ThemePrefsStore.normalizedName(nameDraft)
        guard trimmed != prefs.name else { return }
        update { $0.name = trimmed }
    }

    /// appearance.tsx `previewLabel`: "<salutation>, <name>" or plain "Today".
    public var previewLabel: String {
        let trimmed = ThemePrefsStore.normalizedName(nameDraft)
        return trimmed.isEmpty ? "Today" : "\(Self.salutation(hour: hour())), \(trimmed)"
    }

    /// appearance.tsx `salutation(hour)`.
    public nonisolated static func salutation(hour: Int) -> String {
        if hour < 5 { return "Good night" }
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private func update(_ patch: (inout ThemePrefs) -> Void) {
        var next = prefs
        patch(&next)
        do {
            try ThemePrefsStore.save(next, to: store)
            prefs = ThemePrefsStore.load(from: store)
            saveError = nil
        } catch {
            saveError = "Couldn't save appearance settings: \(error.localizedDescription)"
        }
    }
}
