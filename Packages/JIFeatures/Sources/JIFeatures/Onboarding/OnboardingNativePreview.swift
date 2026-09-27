import SwiftUI

/// §8.5 registry: one entry per onboarding board (`3 Plan & train/08–11`).
struct OnboardingNativePreview: View {
    let step: OnboardingViewModel.Step
    var body: some View {
        if let vm = OnboardingViewModel.fixture(step: step) {
            OnboardingFlowView(model: vm) {}
        } else {
            NativeFixtureUnavailable(screen: "Onboarding")
        }
    }
}
