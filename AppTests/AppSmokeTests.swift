import Testing
import UIKit
@testable import JournalInsight

@Test func appTargetTestsRun() { #expect(1 + 1 == 2) }

#if DEBUG
/// The DEBUG touch overlay only works if the observer sits on SwiftUI's key window and the
/// passthrough overlay window exists — check the wiring at runtime, not by reading code.
@Test @MainActor func touchOverlayIsWiredToTheKeyWindow() {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let overlay = scene?.windows.first { $0 is TouchIndicatorWindow }
    let host = scene?.keyWindow ?? scene?.windows.first { !($0 is TouchIndicatorWindow) }
    #expect(overlay != nil, "overlay window missing; windows=\(scene?.windows.map { type(of: $0) } ?? [])")
    #expect(host?.gestureRecognizers?.contains { $0 is TouchObserverRecognizer } == true)
}
#endif
