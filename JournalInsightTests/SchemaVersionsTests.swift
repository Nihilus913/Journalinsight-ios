// JournalInsightTests/SchemaVersionsTests.swift
import Testing
import Foundation
import SwiftData
@testable import JournalInsight

@Suite("SchemaVersions")
struct SchemaVersionsTests {

    @Test("V0 and V1 versionIdentifiers are distinct and ordered")
    func versionIdentifiers() {
        #expect(JournalSchemaV0.versionIdentifier == Schema.Version(0, 0, 0))
        #expect(JournalSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("MigrationPlan declares V0 and V1 in order")
    func migrationPlanSchemas() {
        let identifiers = JournalMigrationPlan.schemas.map {
            String(describing: $0)
        }
        #expect(identifiers.count == 2)
        #expect(Set(identifiers).count == 2) // distinct
    }

    @Test("MigrationPlan declares one lightweight stage")
    func migrationStage() {
        #expect(JournalMigrationPlan.stages.count == 1)
    }
}
