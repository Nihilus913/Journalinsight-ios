import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Draws an opaque redacted layer over the app whenever `scenePhase != .active`
/// — a snapshot-leak mitigation, independent of vault lock state. Ported
/// verbatim from XC donor commit 4b012de
/// (`JournalInsight/Vault/PrivacyOverlay.swift`).
public struct PrivacyOverlay: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public func body(content: Content) -> some View {
        ZStack {
            content
            if Self.isRedacted(scenePhase) {
                Self.backgroundColor
                    .ignoresSafeArea()
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: scenePhase)
    }

    /// `swift test` runs this package's tests on macOS (only iOS/watchOS
    /// ship in the app), where `Color(.systemBackground)` isn't available.
    static var backgroundColor: Color {
        #if canImport(UIKit)
        Color(.systemBackground)
        #else
        Color(white: 0.05)
        #endif
    }

    public static func isRedacted(_ phase: ScenePhase) -> Bool {
        switch phase {
        case .active: return false
        case .inactive, .background: return true
        @unknown default: return true // fail closed
        }
    }
}

extension View {
    /// Apply the always-on privacy overlay. Anchor at app root.
    public func privacyOverlay() -> some View {
        modifier(PrivacyOverlay())
    }
}
