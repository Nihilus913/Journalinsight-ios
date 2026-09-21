import Foundation
import SwiftUI
import JIDesign
import JIPersistence

// W5a-L1 (P-appearance). Port of `mobile/src/theme/themePrefs.ts` (+ the `ACCENT_OPTIONS`,
// `DYNAMIC_TYPE_SCALE` token tables from `tokens.ts` and `ThemeProvider.tsx`'s mode→scheme
// resolution). Persisted through `PrefStore` (JIPersistence `pref` table, same key name as RN's
// `local_prefs.db` blob) — per-device, user-authored, no hub. Pure values: `nonisolated`.

/// themePrefs.ts `ThemeMode`.
public nonisolated enum ThemeMode: String, Codable, Sendable, CaseIterable, Equatable {
    case system, light, dark

    /// appearance.tsx `MODE_OPTIONS` labels.
    public var label: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }

    /// What the app hands `.preferredColorScheme` — nil = follow the device (RN "system").
    public var preferredColorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }

    /// ThemeProvider.tsx: `scheme = prefs.mode === "system" ? systemScheme : prefs.mode`.
    public func resolvedScheme(system: JIScheme) -> JIScheme {
        switch self { case .system: system; case .light: .light; case .dark: .dark }
    }
}

/// tokens.ts `ACCENT_OPTIONS` (E13-8 personalization accents — a token space separate from the
/// verdict set; picking one re-tints personalization chrome only, never verdict meaning).
public nonisolated enum AccentKey: String, Codable, Sendable, CaseIterable, Equatable {
    case emerald, teal, indigo, orange, fuchsia

    public static let `default`: AccentKey = .emerald

    public var hex: UInt32 {
        switch self {
        case .emerald: 0x4ade80
        case .teal: 0x2dd4bf
        case .indigo: 0x818cf8
        case .orange: 0xfb923c
        case .fuchsia: 0xe879f9
        }
    }

    /// appearance.tsx `ACCENT_LABELS`.
    public var label: String {
        switch self {
        case .emerald: "Emerald"; case .teal: "Teal"; case .indigo: "Indigo"; case .orange: "Orange"; case .fuchsia: "Fuchsia"
        }
    }

    /// B-33 §1: the iOS system tint this accent becomes under `.native`. Names and rawValues are
    /// unchanged so saved prefs survive.
    public var nativeColor: Color {
        switch self {
        case .emerald: .green
        case .teal: .teal
        case .indigo: .indigo
        case .orange: .orange
        case .fuchsia: .pink
        }
    }

    /// B-33 phase B: every surface renders under `.native`, so the classic swatch (`hex`, kept
    /// for the persisted prefs round-trip) no longer resolves to a `Color`. Phase C removes the
    /// `.classic` case and this switch with it.
    public func color(for theme: JITheme) -> Color {
        switch theme { case .classic: nativeColor; case .native: nativeColor }
    }
}

/// tokens.ts `FontScalePreset` — "system" = the device's own text size (RN
/// `PixelRatio.getFontScale()`, here Dynamic Type untouched); the others are fixed multipliers.
public nonisolated enum FontScalePreset: String, Codable, Sendable, CaseIterable, Equatable {
    case system, small, `default`, large, xlarge

    /// tokens.ts `DYNAMIC_TYPE_SCALE`; nil for `system`.
    public var scale: Double? {
        switch self {
        case .system: nil
        case .small: 0.9
        case .default: 1
        case .large: 1.15
        case .xlarge: 1.3
        }
    }

    /// appearance.tsx `FONT_SCALE_OPTIONS` labels.
    public var label: String {
        switch self {
        case .system: "Auto"; case .small: "Small"; case .default: "Default"; case .large: "Large"; case .xlarge: "Extra large"
        }
    }

    /// The SwiftUI equivalent of a fixed multiplier: the `DynamicTypeSize` step whose body-text
    /// size ratio is closest to `scale` (iOS default `.large` = 17 pt → small 15 (0.88), xLarge 19
    /// (1.12), xxLarge 21 (1.24) — the three nearest rungs to 0.9 / 1.15 / 1.3). nil = system.
    public var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .small: .small
        case .default: .large
        case .large: .xLarge
        case .xlarge: .xxLarge
        }
    }
}

/// themePrefs.ts / dynamicScheme.ts `ColorSource` — what the user ASKED for. iOS has no
/// Material You palette, so it always resolves to `.fixed` at render time; the stored choice is
/// left untouched (the RN file's own rule), only the Appearance UI for it is descoped on iOS.
public nonisolated enum ColorSource: String, Codable, Sendable, CaseIterable, Equatable {
    case dynamic, fixed
}

/// themePrefs.ts `ThemePrefs`. `name` is trimmed and capped on save (`reconcile`).
public nonisolated struct ThemePrefs: Codable, Sendable, Equatable {
    public var mode: ThemeMode
    public var accentKey: AccentKey
    public var fontScalePreset: FontScalePreset
    /// Trimmed, ≤ 40 chars. Empty = "no greeting name set yet" → Today shows the plain "Today".
    public var name: String
    public var colorSource: ColorSource

    public static let maxNameLength = 40
    public static let `default` = ThemePrefs(mode: .system, accentKey: .default, fontScalePreset: .system, name: "", colorSource: .dynamic)

    public init(mode: ThemeMode, accentKey: AccentKey, fontScalePreset: FontScalePreset, name: String, colorSource: ColorSource) {
        self.mode = mode
        self.accentKey = accentKey
        self.fontScalePreset = fontScalePreset
        self.name = name
        self.colorSource = colorSource
    }
}

/// `loadThemePrefs` / `saveThemePrefs` over `PrefStore`, with themePrefs.ts's field-by-field
/// `reconcile`: an unknown mode/accent/preset/source (an option since removed, or a blob from a
/// future build) falls back to ITS default, never the whole blob.
public nonisolated enum ThemePrefsStore {
    public static let prefKey = "theme.prefs.v1"

    /// The raw shape a persisted blob may have — every field optional/untyped so a stale or
    /// partial blob still decodes and reconciles instead of throwing.
    private struct Raw: Decodable {
        var mode: String?
        var accentKey: String?
        var fontScalePreset: String?
        var name: String?
        var colorSource: String?
    }

    private static func reconcile(_ raw: Raw?) -> ThemePrefs {
        guard let raw else { return .default }
        let d = ThemePrefs.default
        return ThemePrefs(
            mode: raw.mode.flatMap(ThemeMode.init(rawValue:)) ?? d.mode,
            accentKey: raw.accentKey.flatMap(AccentKey.init(rawValue:)) ?? d.accentKey,
            fontScalePreset: raw.fontScalePreset.flatMap(FontScalePreset.init(rawValue:)) ?? d.fontScalePreset,
            name: raw.name.map(normalizedName) ?? d.name,
            colorSource: raw.colorSource.flatMap(ColorSource.init(rawValue:)) ?? d.colorSource
        )
    }

    /// themePrefs.ts: `name.trim().slice(0, MAX_NAME_LENGTH)`.
    public static func normalizedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ThemePrefs.maxNameLength))
    }

    /// Never throws: an unreadable blob is the same as no blob (defaults).
    public static func load(from store: PrefStore) -> ThemePrefs {
        reconcile(try? store.get(prefKey, as: Raw.self))
    }

    public static func save(_ prefs: ThemePrefs, to store: PrefStore) throws {
        var normalized = prefs
        normalized.name = normalizedName(prefs.name)
        try store.set(prefKey, normalized)
    }
}
