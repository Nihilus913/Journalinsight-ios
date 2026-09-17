import Foundation
import Testing
@testable import JIVault

private struct Vectors: Decodable {
    struct Wrapped: Decodable {
        let version: Int
        let saltHex: String
        let ivHex: String
        let iterations: Int
        let ciphertextB64: String
        let macHex: String
    }
    struct Column: Decodable {
        let plaintext: String
        let ciphertext: String
    }
    let passphrase: String
    let rawKeyHex: String
    let wrapped: Wrapped
    let columns: [Column]
}

/// Vectors generated once with `node` + the HT repo's `mobile/node_modules/
/// crypto-js`, mirroring RN `wrapVaultKey`/`createCipher` (see W4 card).
/// Regeneration script: scratchpad-only, not committed anywhere.
@Suite
struct FoldImportBridgeTests {
    private func loadVectors() throws -> Vectors {
        let url = Bundle.module.url(forResource: "fold_vault_vectors", withExtension: "json")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Vectors.self, from: data)
    }

    @Test
    func unwrapsVaultKeyWithCorrectPassphrase() throws {
        let v = try loadVectors()
        let wrapped = FoldWrappedVaultKey(
            version: v.wrapped.version,
            saltHex: v.wrapped.saltHex,
            ivHex: v.wrapped.ivHex,
            iterations: v.wrapped.iterations,
            ciphertextB64: v.wrapped.ciphertextB64,
            macHex: v.wrapped.macHex
        )
        let rawKeyHex = try FoldImportBridge.unwrapVaultKey(wrapped, passphrase: v.passphrase)
        #expect(rawKeyHex == v.rawKeyHex)
    }

    @Test
    func wrongPassphraseThrowsWrongPassphrase() throws {
        let v = try loadVectors()
        let wrapped = FoldWrappedVaultKey(
            version: v.wrapped.version,
            saltHex: v.wrapped.saltHex,
            ivHex: v.wrapped.ivHex,
            iterations: v.wrapped.iterations,
            ciphertextB64: v.wrapped.ciphertextB64,
            macHex: v.wrapped.macHex
        )
        #expect(throws: FoldImportError.wrongPassphrase) {
            try FoldImportBridge.unwrapVaultKey(wrapped, passphrase: "not-the-passphrase")
        }
    }

    @Test
    func decryptsEveryColumnVector() throws {
        let v = try loadVectors()
        for column in v.columns {
            let decrypted = try FoldImportBridge.decryptColumn(column.ciphertext, rawKeyHex: v.rawKeyHex)
            #expect(decrypted == column.plaintext)
        }
    }

    @Test
    func nonMarkedColumnPassesThroughUnchanged() throws {
        let v = try loadVectors()
        let decrypted = try FoldImportBridge.decryptColumn("legacy plaintext", rawKeyHex: v.rawKeyHex)
        #expect(decrypted == "legacy plaintext")
    }
}
