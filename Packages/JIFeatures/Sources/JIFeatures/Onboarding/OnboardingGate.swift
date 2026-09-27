import SwiftUI
import JIPersistence

/// B-57 W4 first-launch hook: PrefStore `onboarding.completedVersion`; the flow shows when nil.
/// Bump `currentVersion` only when a new required step must reach existing users.
public nonisolated enum OnboardingGate {
    public static let key = "onboarding.completedVersion"
    public static let currentVersion = 1

    public static func needsOnboarding(_ prefs: PrefStore) -> Bool {
        ((try? prefs.get(key, as: Int.self)) ?? nil) == nil
    }

    public static func markCompleted(_ prefs: PrefStore) { try? prefs.set(key, currentVersion) }
}

extension View {
    /// Full-screen on iOS; a sheet on the macOS test host (`fullScreenCover` is iOS-only).
    @ViewBuilder public func onboardingCover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// W-FIX5 fixer (W4-2): item-driven — the content closure receives the model, so the cover can
    /// never be built while the `@State` holding it still reads nil (the black cover with no way out).
    @ViewBuilder public func onboardingCover<Item: Identifiable, C: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item, content: content)
        #else
        self.sheet(item: item, content: content)
        #endif
    }
}

/// W-FIX5 fixer (W4-2): one walk-through per model instance.
extension OnboardingViewModel: Identifiable {}
