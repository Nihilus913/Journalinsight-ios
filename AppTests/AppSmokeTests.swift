import Testing
import UIKit
@testable import JournalInsight

@Test func appTargetTestsRun() { #expect(1 + 1 == 2) }

/// W-FIX2 fixer BUG-15: Info.plist must not pin the interface style — `UIUserInterfaceStyle: Dark`
/// overrode Appearance → System, so the app stayed dark with the device in light.
@Test func infoPlistDoesNotPinTheInterfaceStyle() {
    #expect(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") == nil)
}

#if DEBUG
/// True when some window scene reached `.foregroundActive` — the only state in which
/// `AppDelegate`'s `UIScene.didActivateNotification` observer has installed the overlay.
@MainActor private func aSceneIsForegroundActive() -> Bool {
    UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
}

/// The DEBUG touch overlay only works if the observer sits on SwiftUI's key window and the
/// passthrough overlay window exists — check the wiring at runtime, not by reading code.
///
/// B-35 (W9.5 L2): headless `xcodebuild test` never activates the scene, so the overlay is
/// never installed and the assertion used to fail deterministically. The test is skipped (with
/// this reason) unless a scene is actually `.foregroundActive`; it still runs on a device or a
/// foregrounded simulator.
@Test(.enabled("B-35: no scene is foregroundActive (headless run) — overlay is installed on UIScene.didActivateNotification") {
    await MainActor.run { aSceneIsForegroundActive() }
})
@MainActor func touchOverlayIsWiredToTheKeyWindow() {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
    let overlay = scene?.windows.first { $0 is TouchIndicatorWindow }
    let host = scene?.keyWindow ?? scene?.windows.first { !($0 is TouchIndicatorWindow) }
    #expect(overlay != nil, "overlay window missing; windows=\(scene?.windows.map { type(of: $0) } ?? [])")
    #expect(host?.gestureRecognizers?.contains { $0 is TouchObserverRecognizer } == true)
}
#endif
