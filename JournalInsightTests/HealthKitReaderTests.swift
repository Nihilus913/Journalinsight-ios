// JournalInsightTests/HealthKitReaderTests.swift
import Testing
import Foundation
@testable import JournalInsight

@Suite("HealthKitReaderTests")
struct HealthKitReaderTests {

    @Test("normaliseSleepScore maps 0-100 to 0-1")
    func normaliseSleepScore() {
        #expect(HealthKitReader.normaliseSleepScore(100) == 1.0)
        #expect(HealthKitReader.normaliseSleepScore(0) == 0.0)
        #expect(HealthKitReader.normaliseSleepScore(50) == 0.5)
    }

    @Test("normaliseSleepScore clamps out-of-range values")
    func normaliseSleepScoreClamped() {
        #expect(HealthKitReader.normaliseSleepScore(120) == 1.0)
        #expect(HealthKitReader.normaliseSleepScore(-10) == 0.0)
    }

    @Test("formattedRHR returns bpm string")
    func formattedRHR() {
        #expect(HealthKitReader.formattedRHR(62.0) == "62 bpm")
    }

    @Test("formattedRHR handles nil")
    func formattedRHRNil() {
        #expect(HealthKitReader.formattedRHR(nil) == "—")
    }
}
