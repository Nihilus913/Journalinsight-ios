// JournalInsightTests/FakeKeychain.swift
import Foundation
import CryptoKit
@testable import JournalInsight

/// In-memory KeychainService for unit tests. Configurable to throw at any step.
final class FakeKeychain: KeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: SymmetricKey?

    /// If set, loadMasterKey throws this error instead of returning the stored key.
    var loadError: KeychainError?
    /// If set, storeNewMasterKey throws this error instead of generating one.
    var storeError: KeychainError?
    /// Tracks call counts for assertion in tests.
    private(set) var loadCallCount = 0
    private(set) var storeCallCount = 0

    func loadMasterKey() async throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        loadCallCount += 1
        if let error = loadError { throw error }
        guard let key = storedKey else { throw KeychainError.itemNotFound }
        return key
    }

    func storeNewMasterKey() async throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        storeCallCount += 1
        if let error = storeError { throw error }
        let key = SymmetricKey(size: .bits256)
        storedKey = key
        return key
    }

    func deleteMasterKey() async throws {
        lock.lock(); defer { lock.unlock() }
        storedKey = nil
    }

    /// Test helper — pre-seed a known key for round-trip testing.
    func seedKey(_ key: SymmetricKey) {
        lock.lock(); defer { lock.unlock() }
        storedKey = key
    }
}
