import Foundation
import CommonCrypto

/// Importer-only bridge that reads RN Fold-archive vault material. Never
/// used to write — L4 (Backup) re-seals every decrypted column through
/// `EnvelopeCodec`/`FieldCipher` before it ever touches GRDB.
///
/// Mirrors two RN modules exactly (algorithm + parameter choices, so real
/// archives decrypt byte-for-byte):
///   - `mobile/src/backup/vaultKeyWrap.ts`: PBKDF2-HMAC-SHA256 (210 000
///     iterations) over a passphrase + salt derives 512 bits, split into an
///     AES subkey (bytes 0-31) and an HMAC subkey (bytes 32-63). The wrapped
///     vault key is AES-256-CBC/PKCS7 under the AES subkey; the MAC
///     (HMAC-SHA256 over iv||ciphertext) is verified BEFORE decrypting, so a
///     wrong passphrase fails as `.wrongPassphrase` rather than returning
///     silently-garbled bytes.
///   - `mobile/src/journal/vault.ts`: a `htv1:<ivHex>:<base64ciphertext>`
///     column value, AES-256-CBC/PKCS7 under the raw (unwrapped) vault key.
///     A value not carrying the `htv1:` marker is legacy plaintext and is
///     passed through unchanged, matching RN's `decrypt()`.
public enum FoldImportError: Error, Equatable, Sendable {
    case wrongPassphrase
    case malformedColumn
    case unsupportedVersion
    case cryptoFailure
}

/// Mirrors RN's `WrappedVaultKey` (`vaultKeyWrap.ts`) — the shape a Fold
/// archive's `wrappedVaultKey` field deserializes into.
public struct FoldWrappedVaultKey: Sendable, Equatable {
    public let version: Int
    public let saltHex: String
    public let ivHex: String
    public let iterations: Int
    public let ciphertextB64: String
    public let macHex: String

    public init(version: Int, saltHex: String, ivHex: String, iterations: Int, ciphertextB64: String, macHex: String) {
        self.version = version
        self.saltHex = saltHex
        self.ivHex = ivHex
        self.iterations = iterations
        self.ciphertextB64 = ciphertextB64
        self.macHex = macHex
    }
}

public enum FoldImportBridge {
    /// Mirrors RN `WRAPPED_VAULT_KEY_VERSION`.
    public static let wrappedVaultKeyVersion = 1
    /// Mirrors RN `VAULT_MARKER`.
    static let columnMarker = "htv1:"

    /// Recovers the raw vault key hex (64 lowercase hex chars) from a
    /// Fold-archive wrapped key under `passphrase`. Throws `.wrongPassphrase`
    /// on MAC mismatch (wrong passphrase OR a tampered/corrupt entry) —
    /// mirrors RN `unwrapVaultKey`'s verify-before-decrypt ordering.
    public static func unwrapVaultKey(_ wrapped: FoldWrappedVaultKey, passphrase: String) throws -> String {
        guard wrapped.version == wrappedVaultKeyVersion else { throw FoldImportError.unsupportedVersion }
        guard
            let salt = Data(hexEncoded: wrapped.saltHex),
            let iv = Data(hexEncoded: wrapped.ivHex),
            let ciphertext = Data(base64Encoded: wrapped.ciphertextB64)
        else { throw FoldImportError.malformedColumn }

        let (aesKey, macKey) = try deriveSubkeys(passphrase: passphrase, salt: salt, iterations: wrapped.iterations)

        let expectedMac = try hmacSHA256(key: macKey, data: iv + ciphertext)
        guard expectedMac.hexEncoded == wrapped.macHex.lowercased() else { throw FoldImportError.wrongPassphrase }

        let plainData = try aesCBCDecrypt(ciphertext: ciphertext, key: aesKey, iv: iv)
        guard
            let rawKeyHex = String(data: plainData, encoding: .utf8),
            rawKeyHex.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        else { throw FoldImportError.wrongPassphrase }
        return rawKeyHex
    }

    /// Decrypts one `htv1:`-marked column value under the raw (unwrapped)
    /// vault key hex. Passes a non-marked value through unchanged.
    public static func decryptColumn(_ stored: String, rawKeyHex: String) throws -> String {
        guard stored.hasPrefix(columnMarker) else { return stored }
        let rest = stored.dropFirst(columnMarker.count)
        guard let sep = rest.firstIndex(of: ":") else { throw FoldImportError.malformedColumn }
        let ivHex = String(rest[rest.startIndex..<sep])
        let b64 = String(rest[rest.index(after: sep)...])
        guard
            let iv = Data(hexEncoded: ivHex),
            let ciphertext = Data(base64Encoded: b64),
            let keyData = Data(hexEncoded: rawKeyHex)
        else { throw FoldImportError.malformedColumn }
        let plain = try aesCBCDecrypt(ciphertext: ciphertext, key: keyData, iv: iv)
        guard let str = String(data: plain, encoding: .utf8) else { throw FoldImportError.malformedColumn }
        return str
    }

    // MARK: - CommonCrypto primitives

    private static func deriveSubkeys(passphrase: String, salt: Data, iterations: Int) throws -> (aes: Data, mac: Data) {
        guard let passphraseData = passphrase.data(using: .utf8) else { throw FoldImportError.cryptoFailure }
        let derivedCount = 64 // 512 bits: 32 AES + 32 HMAC
        var derived = [UInt8](repeating: 0, count: derivedCount)
        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            passphraseData.withUnsafeBytes { passBytes -> Int32 in
                salt.withUnsafeBytes { saltBytes -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.bindMemory(to: Int8.self).baseAddress, passphraseData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress, derivedCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw FoldImportError.cryptoFailure }
        let derivedData = Data(derived)
        return (derivedData.prefix(32), derivedData.suffix(32))
    }

    private static func hmacSHA256(key: Data, data: Data) throws -> Data {
        var mac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        mac.withUnsafeMutableBytes { macBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBytes.baseAddress, key.count,
                        dataBytes.baseAddress, data.count,
                        macBytes.baseAddress
                    )
                }
            }
        }
        return Data(mac)
    }

    private static func aesCBCDecrypt(ciphertext: Data, key: Data, iv: Data) throws -> Data {
        let outCapacity = ciphertext.count + kCCBlockSizeAES128
        var outBytes = [UInt8](repeating: 0, count: outCapacity)
        var outLength = 0
        let status = outBytes.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            ciphertext.withUnsafeBytes { inPtr -> CCCryptorStatus in
                key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
                    iv.withUnsafeBytes { ivPtr -> CCCryptorStatus in
                        CCCrypt(
                            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, ciphertext.count,
                            outPtr.baseAddress, outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }
        // Bad key/IV/padding surfaces here as kCCDecodeError — mirrors RN's
        // "wrong passphrase produces a decrypt failure downstream of the MAC
        // check" only for the column path (raw-key decrypt has no MAC).
        guard status == kCCSuccess else { throw FoldImportError.wrongPassphrase }
        return Data(outBytes.prefix(outLength))
    }
}

extension Data {
    init?(hexEncoded hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let byte = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            bytes.append(byte)
            i += 2
        }
        self = Data(bytes)
    }

    var hexEncoded: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
