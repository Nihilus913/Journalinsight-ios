import SwiftUI
import JIDesign

/// B-57 W4 — boards `3 Plan & train/08–11`. Progress bars, "Step n of 4", "Skip for now", one
/// primary button (`.jiPrimary`, the accent). Reopened from GateConfig "Walk me through it again".
public struct OnboardingFlowView: View {
    @Bindable private var model: OnboardingViewModel
    private let onDone: () -> Void
    private let theme = JITheme.native

    public init(model: OnboardingViewModel, onDone: @escaping () -> Void) { self.model = model; self.onDone = onDone }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    Group {
                        switch model.step {
                        case .welcome: OnboardingWelcomeStep()
                        case .baseline: OnboardingBaselineStep(nights: model.nightsSoFar)
                        case .safety: OnboardingSafetyStep(model: model)
                        case .gate: OnboardingGateStep(model: model)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
                    .readableColumn()
                }
                Button { Task { await model.continueTapped() } } label: { Text(model.primaryTitle) }
                    .buttonStyle(.jiPrimary)
                    .padding(.horizontal, 20).padding(.bottom, 16)
                    .readableColumn()
                    .accessibilityIdentifier("onboarding.continue")
            }
            .background(theme.color(.bg))
            .toolbar(.hidden)
        }
        .jiTheme(.native)
        .onChange(of: model.finished) { _, done in if done { onDone() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(OnboardingViewModel.Step.allCases, id: \.self) { s in
                    Capsule().fill(s.rawValue <= model.step.rawValue ? theme.color(.info) : theme.color(.muted).opacity(0.3))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            HStack {
                if model.step != .welcome {
                    Button { model.back() } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Back").tint(theme.color(.info))
                        .accessibilityIdentifier("onboarding.back")
                }
                Text(model.stepLabel).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                Spacer()
                Button("Skip for now") { Task { await model.skip() } }
                    .jiFont(.footnote, weight: .semibold).tint(theme.color(.info))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .padding(.horizontal, 20).padding(.top, 16)
        .readableColumn()
    }
}
