import Foundation
import SwiftUI
import Testing
import JIDesign
import JIPersistence
@testable import JIFeatures

// W5a-L1 (P-appearance). Ports `mobile/__tests__/theme/themePrefs.test.ts` (load/save round-trip,
// field-by-field reconcile) onto `PrefStore`, plus the `AppearanceViewModel` seams the RN screen
// (`app/appearance.tsx`) and `ThemeProvider.tsx` expose: mode → scheme, accent → hex, text-size
// preset → scale, greeting preview.

@MainActor
private func makeStore() throws -> PrefStore { PrefStore(db: try AppDatabase.inMemory()) }

// MARK: - themePrefs.test.ts

@Test @MainActor func loadReturnsTheDefaultPrefsWhenNothingSaved() throws {
    let store = try makeStore()
    #expect(ThemePrefsStore.load(from: store) == ThemePrefs.default)
    #expect(ThemePrefs.default.mode == .system)
    #expect(ThemePrefs.default.accentKey == .emerald)
    #expect(ThemePrefs.default.fontScalePreset == .system)
    #expect(ThemePrefs.default.name == "")
    #expect(ThemePrefs.default.colorSource == .dynamic)
}

/// Exit criterion: "mode (system/light/dark), accent, font-scale persist via `PrefStore` round-trip".
@Test @MainActor func savesAndReloadsAFullPrefsObject() throws {
    let store = try makeStore()
    let prefs = ThemePrefs(mode: .dark, accentKey: .indigo, fontScalePreset: .large, name: "Toby", colorSource: .fixed)
    try ThemePrefsStore.save(prefs, to: store)
    #expect(ThemePrefsStore.load(from: store) == prefs)
    for mode in ThemeMode.allCases {
        try ThemePrefsStore.save(ThemePrefs(mode: mode, accentKey: .teal, fontScalePreset: .small, name: "", colorSource: .dynamic), to: store)
        #expect(ThemePrefsStore.load(from: store).mode == mode)
    }
}

@Test @MainActor func trimsAndLengthCapsThePersistedName() throws {
    let store = try makeStore()
    try ThemePrefsStore.save(ThemePrefs(mode: .light, accentKey: .teal, fontScalePreset: .system, name: "  Toby  ", colorSource: .dynamic), to: store)
    #expect(ThemePrefsStore.load(from: store).name == "Toby")
    let long = String(repeating: "x", count: 60)
    try ThemePrefsStore.save(ThemePrefs(mode: .light, accentKey: .teal, fontScalePreset: .system, name: long, colorSource: .dynamic), to: store)
    #expect(ThemePrefsStore.load(from: store).name.count == ThemePrefs.maxNameLength)
}

/// "an unknown mode falls back to the default mode, other fields keep their saved values" — the
/// stale blob is written raw (a build that had a `sepia` mode), as the RN test simulates.
@Test @MainActor func unknownModeFallsBackFieldByField() throws {
    let store = try makeStore()
    try store.set(ThemePrefsStore.prefKey, ["mode": "sepia", "accent_key": "orange", "font_scale_preset": "xlarge", "name": "Toby", "color_source": "fixed"])
    let loaded = ThemePrefsStore.load(from: store)
    #expect(loaded.mode == ThemePrefs.default.mode)
    #expect(loaded.accentKey == .orange)
    #expect(loaded.fontScalePreset == .xlarge)
    #expect(loaded.name == "Toby")
    #expect(loaded.colorSource == .fixed)
}

@Test @MainActor func unknownAccentFontScaleAndColorSourceFallBackToDefaults() throws {
    let store = try makeStore()
    try store.set(ThemePrefsStore.prefKey, ["mode": "dark", "accent_key": "chartreuse", "font_scale_preset": "huge", "name": "", "color_source": "wallpaper"])
    let loaded = ThemePrefsStore.load(from: store)
    #expect(loaded.mode == .dark)
    #expect(loaded.accentKey == ThemePrefs.default.accentKey)
    #expect(loaded.fontScalePreset == ThemePrefs.default.fontScalePreset)
    #expect(loaded.colorSource == ThemePrefs.default.colorSource)
}

@Test @MainActor func blobMissingColorSourceFallsBackToDefault() throws {
    let store = try makeStore()
    try store.set(ThemePrefsStore.prefKey, ["mode": "dark", "accent_key": "teal", "font_scale_preset": "system", "name": "Toby"])
    let loaded = ThemePrefsStore.load(from: store)
    #expect(loaded.colorSource == ThemePrefs.default.colorSource)
    #expect(loaded.accentKey == .teal)
}

@Test @MainActor func corruptBlobFallsBackToDefaults() throws {
    let store = try makeStore()
    try store.set(ThemePrefsStore.prefKey, 42)
    #expect(ThemePrefsStore.load(from: store) == ThemePrefs.default)
}

// MARK: - tokens.ts (ACCENT_OPTIONS / DYNAMIC_TYPE_SCALE) + ThemeProvider.tsx resolution

@Test func accentOptionsAreVerbatimFromTokensTs() {
    #expect(AccentKey.allCases == [.emerald, .teal, .indigo, .orange, .fuchsia])
    #expect(AccentKey.emerald.hex == 0x4ade80)
    #expect(AccentKey.teal.hex == 0x2dd4bf)
    #expect(AccentKey.indigo.hex == 0x818cf8)
    #expect(AccentKey.orange.hex == 0xfb923c)
    #expect(AccentKey.fuchsia.hex == 0xe879f9)
    #expect(AccentKey.orange.label == "Orange")
}

@Test func fontScalePresetsAreVerbatimFromTokensTs() {
    #expect(FontScalePreset.allCases == [.system, .small, .default, .large, .xlarge])
    #expect(FontScalePreset.system.scale == nil)
    #expect(FontScalePreset.small.scale == 0.9)
    #expect(FontScalePreset.default.scale == 1)
    #expect(FontScalePreset.large.scale == 1.15)
    #expect(FontScalePreset.xlarge.scale == 1.3)
    #expect(FontScalePreset.xlarge.label == "Extra large")
    #expect(FontScalePreset.system.label == "Auto")
    #expect(FontScalePreset.system.dynamicTypeSize == nil)
    #expect(FontScalePreset.default.dynamicTypeSize == .large)
}

/// ThemeProvider.tsx: `scheme = prefs.mode === "system" ? systemScheme : prefs.mode`.
@Test func modeResolvesToSchemeAndPreferredColorScheme() {
    #expect(ThemeMode.system.preferredColorScheme == nil)
    #expect(ThemeMode.light.preferredColorScheme == .light)
    #expect(ThemeMode.dark.preferredColorScheme == .dark)
    #expect(ThemeMode.system.resolvedScheme(system: .light) == .light)
    #expect(ThemeMode.system.resolvedScheme(system: .dark) == .dark)
    #expect(ThemeMode.light.resolvedScheme(system: .dark) == .light)
    #expect(ThemeMode.dark.resolvedScheme(system: .light) == .dark)
    #expect(ThemeMode.light.label == "Light")
}

@Test func salutationMatchesAppearanceTsx() {
    #expect(AppearanceViewModel.salutation(hour: 0) == "Good night")
    #expect(AppearanceViewModel.salutation(hour: 4) == "Good night")
    #expect(AppearanceViewModel.salutation(hour: 5) == "Good morning")
    #expect(AppearanceViewModel.salutation(hour: 11) == "Good morning")
    #expect(AppearanceViewModel.salutation(hour: 12) == "Good afternoon")
    #expect(AppearanceViewModel.salutation(hour: 17) == "Good afternoon")
    #expect(AppearanceViewModel.salutation(hour: 18) == "Good evening")
    #expect(AppearanceViewModel.salutation(hour: 23) == "Good evening")
}

// MARK: - AppearanceViewModel

@Test @MainActor func viewModelSettersPersistImmediately() throws {
    let store = try makeStore()
    let model = AppearanceViewModel(prefs: store, hour: { 9 })
    #expect(model.mode == .system)
    model.setMode(.light)
    model.setAccentKey(.fuchsia)
    model.setFontScalePreset(.xlarge)
    let reloaded = ThemePrefsStore.load(from: store)
    #expect(reloaded.mode == .light)
    #expect(reloaded.accentKey == .fuchsia)
    #expect(reloaded.fontScalePreset == .xlarge)
    // A second model over the same store sees the same state (RN: loadThemePrefs on mount).
    let again = AppearanceViewModel(prefs: store, hour: { 9 })
    #expect(again.mode == .light && again.accentKey == .fuchsia && again.fontScalePreset == .xlarge)
    #expect(again.preferredColorScheme == .light)
    #expect(again.uiAccentHex == AccentKey.fuchsia.hex)
}

/// RN: `commitName` only writes when the trimmed draft differs; the preview is
/// `${salutation(hour)}, ${trimmed}` or plain "Today".
@Test @MainActor func nameDraftCommitsTrimmedAndPreviewsTheGreeting() throws {
    let store = try makeStore()
    let model = AppearanceViewModel(prefs: store, hour: { 14 })
    #expect(model.previewLabel == "Today")
    model.nameDraft = "  Toby "
    #expect(model.previewLabel == "Good afternoon, Toby")
    #expect(ThemePrefsStore.load(from: store).name == "")
    model.commitName()
    #expect(ThemePrefsStore.load(from: store).name == "Toby")
    #expect(model.name == "Toby")
    model.nameDraft = ""
    model.commitName()
    #expect(model.previewLabel == "Today")
    #expect(ThemePrefsStore.load(from: store).name == "")
}

@Test @MainActor func appearanceSectionIsRegisteredInThePreferencesBand() {
    let ids = SettingsRegistry.sections.map(\.id)
    #expect(ids.contains(AppearanceSection.sectionId))
    let section = SettingsRegistry.sections.first { $0.id == AppearanceSection.sectionId }!
    #expect(SettingsGroup(sortKey: section.sortKey) == .preferences)
    #expect(Set(ids).count == ids.count)
}
