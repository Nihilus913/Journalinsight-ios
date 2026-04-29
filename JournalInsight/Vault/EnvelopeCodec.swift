// JournalInsight/Vault/EnvelopeCodec.swift
import Foundation
import CryptoKit
import os

enum EnvelopeError: Error, Equatable {
    case decryptionFailed
    case unsupportedVersion(UInt8)
    case malformed
}

/// Versioned AES-256-GCM envelope codec. Wire format:
///
///   byte 0:        version (currently 0x01)
///   bytes 1...12:  nonce (12 bytes)
///   bytes 13...:   sealed-box ciphertext + 16-byte GCM tag
///
/// AAD: entryID.uuidString.utf8 || schemaVersion.littleEndianBytes
/// Re-associating ciphertext to a different entry/version triggers GCM auth failure.
enum EnvelopeCodec {
    static let currentVersion: UInt8 = 0x01

    struct Envelope {
        var cipher: Data
        var nonce: Data
    }

    static func encode(
        _ body: EntryBody,
        key: SymmetricKey,
        entryID: UUID,
        schemaVersion: Int
    ) throws -> Envelope {
        let plaintext = try JSONEncoder().encode(body)
        let aad = makeAAD(entryID: entryID, schemaVersion: schemaVersion)
        let nonce = AES.GCM.Nonce()
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        } catch {
            Logger.crypto.error("seal failed: \(error.localizedDescription, privacy: .public)")
            throw EnvelopeError.decryptionFailed
        }
        var bytes = Data()
        bytes.append(currentVersion)
        bytes.append(contentsOf: nonce)
        bytes.append(sealed.ciphertext)
        bytes.append(sealed.tag)
        return Envelope(cipher: bytes, nonce: Data(nonce))
    }

    static func decode(
        _ data: Data,
        key: SymmetricKey,
        entryID: UUID,
        schemaVersion: Int
    ) throws -> EntryBody {
        guard let firstByte = data.first else { throw EnvelopeError.malformed }
        guard firstByte == currentVersion else { throw EnvelopeError.unsupportedVersion(firstByte) }
        guard data.count >= 1 + 12 + 16 else { throw EnvelopeError.malformed }
        let nonceBytes = data.subdata(in: 1..<13)
        let tagStart = data.count - 16
        let ciphertext = data.subdata(in: 13..<tagStart)
        let tag = data.subdata(in: tagStart..<data.count)
        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: nonceBytes)
        } catch {
            throw EnvelopeError.malformed
        }
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        } catch {
            throw EnvelopeError.malformed
        }
        let aad = makeAAD(entryID: entryID, schemaVersion: schemaVersion)
        do {
            let plaintext = try AES.GCM.open(sealed, using: key, authenticating: aad)
            return try JSONDecoder().decode(EntryBody.self, from: plaintext)
        } catch is CryptoKitError {
            throw EnvelopeError.decryptionFailed
        } catch is DecodingError {
            throw EnvelopeError.decryptionFailed
        } catch {
            throw EnvelopeError.decryptionFailed
        }
    }

    private static func makeAAD(entryID: UUID, schemaVersion: Int) -> Data {
        var aad = Data()
        aad.append(entryID.uuidString.data(using: .utf8) ?? Data())
        var schemaLE = Int32(schemaVersion).littleEndian
        withUnsafeBytes(of: &schemaLE) { aad.append(contentsOf: $0) }
        return aad
    }
}
