// JournalInsightTests/LockPolicySettingsTests.swift
import Testing
import Foundation
@testable import JournalInsight

@Suite("LockPolicySettings")
struct LockPolicySettingsTests {

    @Test("Default value is fiveMinutes when storage is empty")
    func defaultValue() {
        let suite = UserDefaults(suiteName: "test.LockPolicySettings.empty")!
        suite.removeObject(forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        #expect(settings.current == .fiveMinutes)
    }

    @Test("Reads stored value")
    func readsStoredValue() {
        let suite = UserDefaults(suiteName: "test.LockPolicySettings.read")!
        suite.set(LockPolicy.oneMinute.rawValue, forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        #expect(settings.current == .oneMinute)
    }

    @Test("Writing updates UserDefaults")
    func writesValue() {
        let suite = UserDefaults(suiteName: "test.LockPolicySettings.write")!
        suite.removeObject(forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        settings.current = .fifteenMinutes
        #expect(suite.string(forKey: StorageKeys.lockPolicy) == "fifteenMinutes")
    }

    @Test("Falls back to default for unknown raw value")
    func unknownRawValue() {
        let suite = UserDefaults(suiteName: "test.LockPolicySettings.unknown")!
        suite.set("garbage_value", forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        #expect(settings.current == .fiveMinutes)
    }
}
