// JournalInsightTests/EnvelopeCodecTests.swift
import Testing
import Foundation
import CryptoKit
@testable import JournalInsight

@Suite("EnvelopeCodec")
struct EnvelopeCodecTests {
    private let key = SymmetricKey(size: .bits256)
    private let entryID = UUID()

    @Test("encode then decode produces same EntryBody")
    func roundTrip() throws {
        let original = EntryBody(text: "hello world", mood: .good, tags: ["a", "b"])
        let envelope = try EnvelopeCodec.encode(original, key: key, entryID: entryID, schemaVersion: 1)
        let decoded = try EnvelopeCodec.decode(envelope.cipher, key: key, entryID: entryID, schemaVersion: 1)
        #expect(decoded == original)
    }

    @Test("decode with wrong key throws decryptionFailed")
    func wrongKey() throws {
        let body = EntryBody(text: "x")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        let wrongKey = SymmetricKey(size: .bits256)
        #expect(throws: EnvelopeError.decryptionFailed) {
            _ = try EnvelopeCodec.decode(envelope.cipher, key: wrongKey, entryID: entryID, schemaVersion: 1)
        }
    }

    @Test("decode with tampered ciphertext throws")
    func tamperedCiphertext() throws {
        let body = EntryBody(text: "hello")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        var tampered = envelope.cipher
        // Flip a byte deep in the ciphertext (past version byte + nonce + first data byte)
        let flipIndex = tampered.count - 5
        tampered[flipIndex] ^= 0xFF
        #expect(throws: EnvelopeError.decryptionFailed) {
            _ = try EnvelopeCodec.decode(tampered, key: key, entryID: entryID, schemaVersion: 1)
        }
    }

    @Test("decode with mismatched entry ID (AAD) throws")
    func aadEntryIDMismatch() throws {
        let body = EntryBody(text: "hello")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        let differentID = UUID()
        #expect(throws: EnvelopeError.decryptionFailed) {
            _ = try EnvelopeCodec.decode(envelope.cipher, key: key, entryID: differentID, schemaVersion: 1)
        }
    }

    @Test("decode with mismatched schemaVersion throws")
    func aadSchemaVersionMismatch() throws {
        let body = EntryBody(text: "hello")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        #expect(throws: EnvelopeError.decryptionFailed) {
            _ = try EnvelopeCodec.decode(envelope.cipher, key: key, entryID: entryID, schemaVersion: 2)
        }
    }

    @Test("two encodes of same body produce different ciphertexts")
    func nonceUniqueness() throws {
        let body = EntryBody(text: "same")
        let e1 = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        let e2 = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        #expect(e1.cipher != e2.cipher)
        #expect(e1.nonce != e2.nonce)
    }

    @Test("envelope starts with version byte 0x01")
    func versionByte() throws {
        let body = EntryBody(text: "x")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        #expect(envelope.cipher.first == 0x01)
    }

    @Test("nonce is 12 bytes")
    func nonceLength() throws {
        let body = EntryBody(text: "x")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        #expect(envelope.nonce.count == 12)
    }

    @Test("decode rejects unknown version byte")
    func unknownVersion() throws {
        let body = EntryBody(text: "x")
        var envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        envelope.cipher[0] = 0xFF                       // unknown version
        #expect(throws: EnvelopeError.unsupportedVersion(0xFF)) {
            _ = try EnvelopeCodec.decode(envelope.cipher, key: key, entryID: entryID, schemaVersion: 1)
        }
    }
}
