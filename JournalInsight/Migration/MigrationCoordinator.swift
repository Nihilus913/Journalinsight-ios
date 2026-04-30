// JournalInsight/Migration/MigrationCoordinator.swift
import Foundation
import SwiftData
import CryptoKit
import os

@MainActor
struct MigrationCoordinator {

    /// Number of `JournalEntry` rows still at v0 plaintext (`schemaVersion == 0`).
    static func pendingCount(in ctx: ModelContext) throws -> Int {
        let predicate = #Predicate<JournalEntry> { $0.schemaVersion == 0 }
        let descriptor = FetchDescriptor<JournalEntry>(predicate: predicate)
        return try ctx.fetchCount(descriptor)
    }

    /// Number of rows that failed Stage-2 encryption and are quarantined (`schemaVersion == -1`).
    static func quarantineCount(in ctx: ModelContext) throws -> Int {
        let predicate = #Predicate<JournalEntry> { $0.schemaVersion == -1 }
        let descriptor = FetchDescriptor<JournalEntry>(predicate: predicate)
        return try ctx.fetchCount(descriptor)
    }
}
