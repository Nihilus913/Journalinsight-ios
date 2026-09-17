import Testing
@testable import JIVault

@Suite
struct VaultManagerTests {
    @Test
    func startsLocked() async {
        let manager = VaultManager(keychain: FakeKeychain())
        let status = await manager.status
        #expect(status == .locked)
    }

    @Test
    func unlockGeneratesKeyOnFirstRunAndReturnsWorkingCipher() async throws {
        let manager = VaultManager(keychain: FakeKeychain())
        let cipher = try await manager.unlock()
        let sealed = try cipher.seal("plaintext")
        let opened = try cipher.open(sealed)
        #expect(opened == "plaintext")
        let status = await manager.status
        #expect(status == .unlocked(IdentityCipher())) // payload-blind ==
    }

    @Test
    func unlockTwiceReusesSameSessionKey() async throws {
        let manager = VaultManager(keychain: FakeKeychain())
        let cipher1 = try await manager.unlock()
        let cipher2 = try await manager.unlock()
        let sealed = try cipher1.seal("same key")
        // If cipher2 held a different key this would throw.
        let opened = try cipher2.open(sealed)
        #expect(opened == "same key")
    }

    @Test
    func lockDropsSessionCipher() async throws {
        let manager = VaultManager(keychain: FakeKeychain())
        _ = try await manager.unlock()
        await manager.lock()
        let status = await manager.status
        #expect(status == .locked)
    }

    @Test
    func purgeDeletesKeychainItemAndLocks() async throws {
        let keychain = FakeKeychain()
        let manager = VaultManager(keychain: keychain)
        _ = try await manager.unlock()
        try await manager.purge()
        let status = await manager.status
        #expect(status == .locked)
        let raw = await keychain.rawRead()
        #expect(raw == nil)
        await #expect(throws: KeychainError.itemNotFound) {
            try await keychain.loadMasterKey()
        }
    }
}
