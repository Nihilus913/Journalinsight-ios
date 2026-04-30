// JournalInsight/Migration/MigrationSheet.swift
import SwiftUI

struct MigrationSheet: View {
    enum State: Equatable {
        case idle
        case encrypting(current: Int, total: Int)
        case done
        case failed(message: String)
    }

    @Binding var state: State
    var onContinue: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            iconLayer
            textLayer
            Spacer()
            controlLayer
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private var iconLayer: some View {
        switch state {
        case .idle:
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
        case .encrypting:
            ProgressView()
                .controlSize(.large)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var textLayer: some View {
        switch state {
        case .idle:
            VStack(spacing: 8) {
                Text("Setting up encrypted storage")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Your journal is moving to encrypted, end-to-end iCloud storage. This takes a few seconds. Tap Continue to authenticate.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        case .encrypting(let current, let total):
            VStack(spacing: 12) {
                Text("Encrypting your journal")
                    .font(.title3.bold())
                ProgressView(value: Double(current), total: Double(total))
                    .progressViewStyle(.linear)
                Text("Encrypting entry \(current) of \(total)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done:
            Text("Done!")
                .font(.title2.bold())
        case .failed(let message):
            VStack(spacing: 8) {
                Text("Migration paused")
                    .font(.title3.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var controlLayer: some View {
        switch state {
        case .idle:
            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .encrypting:
            EmptyView()
        case .done:
            EmptyView()
        case .failed:
            Button(action: onRetry) {
                Text("Retry")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

#Preview("Idle") {
    StateWrapper(initial: .idle)
}

#Preview("Encrypting") {
    StateWrapper(initial: .encrypting(current: 14, total: 22))
}

#Preview("Done") {
    StateWrapper(initial: .done)
}

#Preview("Failed") {
    StateWrapper(initial: .failed(message: "Some entries couldn't be encrypted."))
}

private struct StateWrapper: View {
    @State private var state: MigrationSheet.State
    init(initial: MigrationSheet.State) { _state = .init(initialValue: initial) }
    var body: some View {
        MigrationSheet(state: $state, onContinue: {}, onRetry: {})
    }
}
