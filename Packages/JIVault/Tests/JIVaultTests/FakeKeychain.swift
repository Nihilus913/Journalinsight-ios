import Foundation
import CryptoKit
@testable import JIVault

/// In-memory `KeychainService` double. Adapted from XC donor commit 4b012de
/// (`JournalInsightTests/FakeKeychain.swift`).
actor FakeKeychain: KeychainService {
    private var stored: Data?

    func loadMasterKey() async throws -> SymmetricKey {
        guard let data = stored else { throw KeychainError.itemNotFound }
        return SymmetricKey(data: data)
    }

    func storeNewMasterKey() async throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        stored = key.withUnsafeBytes { Data($0) }
        return key
    }

    func deleteMasterKey() async throws {
        stored = nil
    }

    /// Test-only introspection — mirrors what a raw `SecItemCopyMatching`
    /// read would answer.
    func rawRead() -> Data? { stored }
}
