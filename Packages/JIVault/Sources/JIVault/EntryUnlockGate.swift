import SwiftUI

/// Wraps any view that needs to display vault-decrypted content, without
/// JIVault knowing what that content is (JIVault has no JICore/JIPersistence
/// dependency — see W4 card). Generalizes XC donor commit 4b012de's
/// `EntryUnlockGate` (which was hard-wired to `JournalEntry`/`EntryRepository`)
/// into an `unlock` closure + generic `Value`, so L1 (Journal) and L2 (Mind)
/// can each instantiate it against their own store's decrypt call.
///
/// States:
///   - `.idle`      — vault sealed, show "🔒 Tap to unlock" pill
///   - `.unlocking` — `unlock()` in flight, show progress
///   - `.unlocked`  — render `content(value)`
///   - `.failed`    — show a "Couldn't unlock" pill with the error message
public struct EntryUnlockGate<Value: Equatable & Sendable, Content: View>: View {
    public enum Phase: Equatable {
        case idle
        case unlocking
        case unlocked(Value)
        case failed(message: String)
    }

    private let unlock: @Sendable () async throws -> Value
    private let content: (Value) -> Content

    @State private var phase: Phase = .idle

    public init(
        unlock: @escaping @Sendable () async throws -> Value,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.unlock = unlock
        self.content = content
    }

    public var body: some View {
        Group {
            switch phase {
            case .idle:
                lockedPill
            case .unlocking:
                ProgressView().controlSize(.small)
            case .unlocked(let value):
                content(value)
            case .failed(let message):
                failedPill(message: message)
            }
        }
    }

    private var lockedPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
            Text("Tap to unlock").font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
        .onTapGesture { Task { await tryUnlock() } }
    }

    private func failedPill(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Couldn't unlock").font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
        .help(message)
        .accessibilityLabel("Couldn't unlock: \(message)")
        .onTapGesture { Task { await tryUnlock() } }
    }

    private func tryUnlock() async {
        phase = .unlocking
        do {
            let value = try await unlock()
            phase = .unlocked(value)
        } catch {
            phase = .failed(message: (error as? LocalizedError)?.errorDescription ?? "Unknown")
        }
    }
}
