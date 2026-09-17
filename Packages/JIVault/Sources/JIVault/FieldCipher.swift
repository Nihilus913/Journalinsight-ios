import Foundation
import CryptoKit

/// Column-level cipher used by JIPersistence stores to seal/open the
/// vaulted TEXT columns from `v3_capture` (entries.text/mood,
/// mind_checkin.mood/note/stress/energy/dosed/irritability/restlessness/
/// appetite, mind_event.type/prodrome/severity — see W4 card).
///
/// Mirrors RN's `FieldCipher` (`mobile/src/journal/vault.ts`): `seal`
/// encrypts, `open` decrypts a value this cipher (or a prior version of it)
/// produced. Unlike RN's `decrypt` (sync), `open` is throwing — a tampered
/// or foreign-key envelope must fail loudly rather than return garbage.
public protocol FieldCipher: Sendable {
    func seal(_ plain: String) throws -> String
    func open(_ stored: String) throws -> String
}

/// Identity cipher — the default for every store constructor, exactly like
/// RN's `NOOP_CIPHER`. Existing callers/tests that don't care about
/// encryption get byte-for-byte passthrough.
public struct IdentityCipher: FieldCipher {
    public init() {}
    public func seal(_ plain: String) throws -> String { plain }
    public func open(_ stored: String) throws -> String { stored }
}

/// Production cipher backed by `EnvelopeCodec` + a `VaultManager`-issued
/// session key. `open` passes a non-envelope string through unchanged
/// (mirrors RN `vault.ts`'s `decrypt` — a value that somehow escaped
/// encryption still reads back instead of throwing).
struct EnvelopeFieldCipher: FieldCipher {
    let key: SymmetricKey

    func seal(_ plain: String) throws -> String {
        try EnvelopeCodec.seal(plain, key: key)
    }

    func open(_ stored: String) throws -> String {
        guard EnvelopeCodec.isEnvelope(stored) else { return stored }
        return try EnvelopeCodec.open(stored, key: key)
    }
}
