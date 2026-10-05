import Foundation
import Testing
@testable import JICompute

/// B-99 p3: registry invariants + the diet_quality `.computed` entry.
@Suite struct ParityRegistryTests {
    @Test func dietQualityIsComputedAndPointsToPort() {
        #expect(ParityRegistry.source(for: DietQuality.registryKey) == .computed)
        #expect(ParityRegistry.implementation(for: DietQuality.registryKey) == "JICompute.DietQuality")
        #expect(ParityRegistry.entry(for: DietQuality.registryKey).notes.contains("B-99"))
    }

    @Test func everyImplementationIsAComputedEntry() {
        for key in ParityRegistry.implementations.keys {
            #expect(ParityRegistry.source(for: key) == .computed, "\(key) has an implementation but is not .computed")
        }
    }

    @Test func everyEntryHasNotes() {
        for (key, e) in ParityRegistry.entries {
            #expect(!e.notes.trimmingCharacters(in: .whitespaces).isEmpty, "\(key)")
        }
    }

    @Test func unregisteredDefaultsToHub() {
        #expect(ParityRegistry.source(for: "some_unregistered_metric_xyz") == .hub)
    }
}
