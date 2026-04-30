// JournalInsightTests/MigrationCoordinatorTests.swift
import Testing
import Foundation
import SwiftData
import CryptoKit
@testable import JournalInsight

@MainActor
@Suite("MigrationCoordinator — counts")
struct MigrationCoordinatorCountTests {

    private func makeContext() throws -> ModelContext {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: JournalEntry.self, Goal.self, Tag.self,
            configurations: cfg
        )
        return ModelContext(container)
    }

    @Test("pendingCount on empty context is 0")
    func emptyPending() throws {
        let ctx = try makeContext()
        #expect(try MigrationCoordinator.pendingCount(in: ctx) == 0)
    }

    @Test("pendingCount counts only schemaVersion == 0")
    func mixedPending() throws {
        let ctx = try makeContext()
        let v0 = JournalEntry(date: .now, text: "v0", duration: 600)        // schemaVersion = 0 by default
        let v1 = JournalEntry(date: .now, text: "v1", duration: 600); v1.schemaVersion = 1
        let q  = JournalEntry(date: .now, text: "q",  duration: 600); q.schemaVersion = -1
        ctx.insert(v0); ctx.insert(v1); ctx.insert(q)
        try ctx.save()
        #expect(try MigrationCoordinator.pendingCount(in: ctx) == 1)
        #expect(try MigrationCoordinator.quarantineCount(in: ctx) == 1)
    }
}
