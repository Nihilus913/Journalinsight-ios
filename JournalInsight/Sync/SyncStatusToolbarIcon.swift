// JournalInsight/Sync/SyncStatusToolbarIcon.swift
import SwiftUI

struct SyncStatusToolbarIcon: View {
    let status: SyncStatus

    var body: some View {
        switch status {
        case .syncing, .idle:
            EmptyView()
        case .paused(let reason):
            label(systemImage: iconName(for: reason), tint: .orange, accessibility: pausedLabel(for: reason))
        case .error(let msg):
            label(systemImage: "exclamationmark.icloud.fill", tint: .red, accessibility: msg)
        }
    }

    private func label(systemImage: String, tint: Color, accessibility: String) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(tint)
            .accessibilityLabel(accessibility)
    }

    private func iconName(for reason: PauseReason) -> String {
        switch reason {
        case .notSignedIntoiCloud, .iCloudKeychainUnavailable: return "icloud.slash"
        case .networkOffline:                                  return "wifi.slash"
        case .schemaMismatch:                                  return "exclamationmark.icloud"
        }
    }

    private func pausedLabel(for reason: PauseReason) -> String {
        switch reason {
        case .notSignedIntoiCloud:        return "Sync paused — sign into iCloud."
        case .iCloudKeychainUnavailable:  return "Sync paused — enable iCloud Keychain."
        case .networkOffline:             return "Sync paused — offline."
        case .schemaMismatch:             return "Sync paused — updating."
        }
    }
}
