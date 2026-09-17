import Foundation
import Testing
import CryptoKit
@testable import JIVault

@Suite
struct EnvelopeCodecTests {
    @Test
    func roundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try EnvelopeCodec.seal("hello vault", key: key)
        #expect(EnvelopeCodec.isEnvelope(sealed))
        let opened = try EnvelopeCodec.open(sealed, key: key)
        #expect(opened == "hello vault")
    }

    @Test
    func nonEnvelopeStringPassesThroughOpen() throws {
        let key = SymmetricKey(size: .bits256)
        let opened = try EnvelopeCodec.open("plain legacy value", key: key)
        #expect(opened == "plain legacy value")
    }

    @Test
    func tamperedCiphertextThrows() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try EnvelopeCodec.seal("secret", key: key)
        var b64 = String(sealed.dropFirst(EnvelopeCodec.marker.count))
        var data = Data(base64Encoded: b64)!
        // Flip a byte inside the ciphertext region (after version+nonce).
        data[data.count - 1] ^= 0xFF
        b64 = data.base64EncodedString()
        let tampered = EnvelopeCodec.marker + b64
        #expect(throws: EnvelopeError.self) {
            try EnvelopeCodec.open(tampered, key: key)
        }
    }

    @Test
    func wrongKeyThrows() throws {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let sealed = try EnvelopeCodec.seal("secret", key: key1)
        #expect(throws: EnvelopeError.self) {
            try EnvelopeCodec.open(sealed, key: key2)
        }
    }

    @Test
    func malformedBase64Throws() throws {
        let key = SymmetricKey(size: .bits256)
        #expect(throws: EnvelopeError.self) {
            try EnvelopeCodec.open("jiv1:not-valid-base64!!!", key: key)
        }
    }
}
