// JournalInsight/Vault/EntryUnlockGate.swift
import SwiftUI
import SwiftData

/// Wraps any view that needs to display decrypted entry content.
///
/// States:
///   - `.locked`        — vault sealed, show "🔒 Tap to unlock" pill
///   - `.unlocking`     — biometric prompt in flight, show progress
///   - `.unlocked(body)` — render `content(body)`
///   - `.failed`        — show ⚠ pill
///
/// Tapping the locked pill triggers `await repo.body(for:)`, which kicks
/// the biometric prompt. On success the gate flips to `.unlocked`.
struct EntryUnlockGate<Content: View>: View {
    let entry: JournalEntry
    let repo: EntryRepository
    @ViewBuilder var content: (EntryBody) -> Content

    @State private var phase: Phase = .idle

    enum Phase: Equatable {
        case idle
        case unlocking
        case unlocked(EntryBody)
        case failed(message: String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.unlocking, .unlocking): return true
            case (.unlocked(let a), .unlocked(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .idle:
                lockedPill                                      // tap-only — no auto biometric prompt
            case .unlocking:
                ProgressView()
                    .controlSize(.small)
            case .unlocked(let body):
                content(body)
            case .failed(let message):
                failedPill(message: message)
            }
        }
    }

    private var lockedPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
            Text("Tap to unlock")
                .font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
        .onTapGesture { Task { await tryUnlock(force: true) } }
    }

    private func failedPill(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Couldn't unlock")
                .font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
        .help(message)
        .accessibilityLabel("Couldn't unlock: \(message)")
        .onTapGesture { Task { await tryUnlock(force: true) } }
    }

    private func tryUnlock(force: Bool = false) async {
        if case .unlocked = phase, !force { return }
        phase = .unlocking
        do {
            let body = try await repo.body(for: entry)
            phase = .unlocked(body)
        } catch VaultError.userCancelled {
            phase = .idle                                  // back to pill
        } catch {
            phase = .failed(message: (error as? LocalizedError)?.errorDescription ?? "Unknown")
        }
    }
}
