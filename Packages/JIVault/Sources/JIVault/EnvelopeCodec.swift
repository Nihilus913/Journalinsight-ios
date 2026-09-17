import Foundation
import CryptoKit

/// Errors from a malformed/tampered/foreign-version envelope. Adapted from
/// XC donor commit 4b012de (`JournalInsight/Vault/EnvelopeCodec.swift`).
public enum EnvelopeError: Error, Equatable, Sendable {
    case decryptionFailed
    case unsupportedVersion(UInt8)
    case malformed
}

/// Versioned, string-carried AES-256-GCM envelope for a single TEXT column
/// (donor `EnvelopeCodec` sealed a struct `EntryBody`; this package seals a
/// bare `String` since `FieldCipher` operates at the column level, matching
/// RN `vault.ts`'s per-column granularity).
///
/// Wire format (base64 of):
///   byte 0:        version (currently 0x01)
///   bytes 1...12:  AES-GCM nonce (12 bytes)
///   bytes 13...:   ciphertext + 16-byte GCM tag
/// stored as `"jiv1:" + base64(...)`. The `jiv1:` marker lets `open` pass a
/// non-envelope string through unchanged, mirroring RN's `htv1:` marker in
/// `vault.ts`.
enum EnvelopeCodec {
    static let marker = "jiv1:"
    static let currentVersion: UInt8 = 0x01

    static func isEnvelope(_ value: String) -> Bool {
        value.hasPrefix(marker)
    }

    static func seal(_ plaintext: String, key: SymmetricKey) throws -> String {
        let nonce = AES.GCM.Nonce()
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key, nonce: nonce)
        } catch {
            throw EnvelopeError.decryptionFailed
        }
        var bytes = Data([currentVersion])
        bytes.append(contentsOf: nonce)
        bytes.append(sealed.ciphertext)
        bytes.append(sealed.tag)
        return marker + bytes.base64EncodedString()
    }

    static func open(_ stored: String, key: SymmetricKey) throws -> String {
        guard stored.hasPrefix(marker) else { return stored }
        let b64 = String(stored.dropFirst(marker.count))
        guard let data = Data(base64Encoded: b64) else { throw EnvelopeError.malformed }
        guard let firstByte = data.first else { throw EnvelopeError.malformed }
        guard firstByte == currentVersion else { throw EnvelopeError.unsupportedVersion(firstByte) }
        guard data.count >= 1 + 12 + 16 else { throw EnvelopeError.malformed }
        let nonceBytes = data.subdata(in: 1..<13)
        let tagStart = data.count - 16
        let ciphertext = data.subdata(in: 13..<tagStart)
        let tag = data.subdata(in: tagStart..<data.count)
        let nonce: AES.GCM.Nonce
        let sealed: AES.GCM.SealedBox
        do {
            nonce = try AES.GCM.Nonce(data: nonceBytes)
            sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        } catch {
            throw EnvelopeError.malformed
        }
        do {
            let plaintext = try AES.GCM.open(sealed, using: key)
            guard let str = String(data: plaintext, encoding: .utf8) else {
                throw EnvelopeError.decryptionFailed
            }
            return str
        } catch let error as EnvelopeError {
            throw error
        } catch {
            throw EnvelopeError.decryptionFailed
        }
    }
}
