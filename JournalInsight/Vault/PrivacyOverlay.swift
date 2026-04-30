import SwiftUI

/// Draws an opaque redacted layer over the app whenever `scenePhase != .active`.
/// Independent of vault unlock state — purely a snapshot-leak mitigation.
/// Closes audit S-2 from CODE_REVIEW.html.
struct PrivacyOverlay: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        ZStack {
            content
            if Self.isRedacted(scenePhase) {
                Color(.systemBackground)
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

    static func isRedacted(_ phase: ScenePhase) -> Bool {
        switch phase {
        case .active:                return false
        case .inactive, .background: return true
        @unknown default:            return true       // fail closed
        }
    }
}

extension View {
    /// Apply the always-on privacy overlay. Anchor at app root.
    func privacyOverlay() -> some View {
        modifier(PrivacyOverlay())
    }
}
