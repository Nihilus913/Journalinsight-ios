// JournalInsight/Sync/SyncStatus.swift
import Foundation

enum SyncStatus: Equatable {
    case syncing
    case idle
    case paused(PauseReason)
    case error(String)
}

enum PauseReason: Equatable {
    case notSignedIntoiCloud
    case iCloudKeychainUnavailable
    case networkOffline
    case schemaMismatch
}
