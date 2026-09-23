import SwiftUI
import JIDesign

/// Settings section (W2h, B-9): fills the Garmin → Apple Health delta. Embedded in
/// `ConnectionSheet`. Purely a view over `HealthBackloadViewModel.Phase` — no HealthKit import
/// here (JIFeatures never imports JIHealthKit; see the wave card).
public struct HealthBackloadSection: View {
    @Environment(\.jiTheme) private var theme
    private let model: HealthBackloadViewModel

    public init(model: HealthBackloadViewModel) {
        self.model = model
    }

    public var body: some View {
        Section("Apple Health backload") {
            Text("Fill the gap where Garmin Connect didn't write to Apple Health: sleep, resting HR, steps, energy, VO₂ max, workouts, heart rate, respiration, SpO₂, HRV, floors climbed and walking distance.")
                .font(.footnote)
                .foregroundStyle(theme.color(.muted))
            LabeledContent("Last synced day", value: model.lastSyncedDay ?? "never")
                .font(.footnote)
            LabeledContent("Last Apple upload", value: model.lastAppleUpload ?? "never")
                .font(.footnote)
            statusRow
            Button("Backload to Apple Health") { Task { await model.start() } }
                .disabled(model.isRunning)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .authorizing:
            HStack { ProgressView(); Text("Requesting Health access…") }
        case .starting:
            HStack { ProgressView(); Text("Health access granted · writing the first month…") }
        case .running(let monthIndex, let monthCount, let written, let skipped):
            VStack(alignment: .leading, spacing: 4) {
                HStack { ProgressView(); Text("Month \(monthIndex) of \(monthCount)") }
                Text("\(written) written · \(skipped) skipped").font(.footnote).foregroundStyle(theme.color(.muted))
            }
        case .done(let summary):
            VStack(alignment: .leading, spacing: 4) {
                Text("Done: \(summary.written) written, \(summary.skipped) skipped.")
                    .foregroundStyle(theme.color(.go))
                if !summary.failed.isEmpty {
                    Text("\(summary.failed.count) samples couldn't be written.")
                        .font(.footnote)
                        .foregroundStyle(theme.color(.danger))
                }
            }
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(theme.color(.danger))
        }
    }
}
