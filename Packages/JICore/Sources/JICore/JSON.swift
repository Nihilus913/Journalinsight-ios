import Foundation

/// snake_case wire format; the hub's `YYYY-MM-DD` dates and timestamps stay `String` in DTOs
/// (no ISO-8601 date strategy — decode/encode them as plain strings).
///
/// `decoder`/`encoder` are computed, not stored `let`s: `JSONDecoder`/`JSONEncoder` are not
/// `Sendable`, so a stored static constant on this enum would be a strict-concurrency error
/// under Swift 6. A fresh instance per access keeps `JSON.decoder` / `JSON.encoder` safe to
/// call from any isolation context.
public enum JSON {
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
