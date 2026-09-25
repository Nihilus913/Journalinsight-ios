import Foundation
import SwiftUI
import Testing
import JIDesign
import JIPersistence
@testable import JIFeatures
#if canImport(UIKit)
import UIKit
#endif

// W-FIX2 BUG-15: the app root follows the system, or the Appearance choice, and the choice
// survives a relaunch — it used to be `.preferredColorScheme(.dark)`, unconditional.

@MainActor
private func makeStore() throws -> PrefStore { PrefStore(db: try AppDatabase.inMemory()) }

@Test @MainActor func rootFollowsTheSystemByDefault() throws {
    let model = AppThemeModel(prefs: try makeStore(), applyAccent: { _ in })
    #expect(model.mode == .system)
    #expect(model.preferredColorScheme == nil)
}

@Test @MainActor func rootPicksUpAnAppearanceChoiceLive() throws {
    let store = try makeStore()
    let root = AppThemeModel(prefs: store, applyAccent: { _ in })
    let appearance = AppearanceViewModel(prefs: store)
    appearance.setMode(.light)
    #expect(root.mode == .light)
    #expect(root.preferredColorScheme == .light)
    appearance.setMode(.system)
    #expect(root.preferredColorScheme == nil)
}

@Test @MainActor func theChoiceSurvivesARelaunch() throws {
    let store = try makeStore()
    AppearanceViewModel(prefs: store).setMode(.dark)
    let relaunched = AppThemeModel(prefs: store, applyAccent: { _ in })
    #expect(relaunched.mode == .dark)
}

@Test @MainActor func accentIsPushedToTheDesignSystem() throws {
    let store = try makeStore()
    var applied: [Color] = []
    let root = AppThemeModel(prefs: store, applyAccent: { applied.append($0) })
    #expect(applied.last == AccentKey.emerald.nativeColor)
    AppearanceViewModel(prefs: store).setAccentKey(.teal)
    #expect(root.accentKey == .teal)
    #expect(applied.last == AccentKey.teal.nativeColor)
}

#if canImport(UIKit)
@Test func themeModeMapsToTheWindowInterfaceStyle() {
    #expect(ThemeMode.system.userInterfaceStyle == .unspecified)
    #expect(ThemeMode.light.userInterfaceStyle == .light)
    #expect(ThemeMode.dark.userInterfaceStyle == .dark)
}
#endif
