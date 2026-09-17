import JIVault

// Re-exports for `JIPersistenceTests` (BackupTests.swift). The JIPersistence
// test target intentionally does NOT declare a `JIVault` package dependency
// — `Package.swift` is frozen (wave W4 card, after L0). `@testable import
// JIPersistence` already exposes this module's internal API, so naming the
// underlying JIVault types here (same type, just a second name) lets the
// tests construct a fake `KeychainService`, use `IdentityCipher`/
// `FieldCipher`, drive `VaultManager`, and match `KeychainError` cases
// without the test target importing JIVault directly.
public typealias KeychainService = JIVault.KeychainService
public typealias KeychainError = JIVault.KeychainError
public typealias FieldCipher = JIVault.FieldCipher
public typealias IdentityCipher = JIVault.IdentityCipher
public typealias VaultManager = JIVault.VaultManager
