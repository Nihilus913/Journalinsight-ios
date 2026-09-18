import Foundation

/// Pure integrity checksum for a table's row dump — mirrors RN
/// `checksum.ts`'s `fnv1aHex` (FNV-1a, 32-bit), used the same way RN uses
/// it: catching accidental corruption/truncation of an archive file, not a
/// cryptographic boundary (the vault already owns "protect sensitive
/// content" via AES-GCM at the column level; this runs over ciphertext
/// bytes it never needs to understand).
///
/// The value IS compared against one RN computed: a real Fold archive
/// carries `checksumFor = fnv1aHex(JSON.stringify(rows))` per table and
/// `BackupImporter.parse` rejects a mismatch as `.corrupted`. So this has
/// to reproduce V8's `JSON.stringify` byte-for-byte over rows in their
/// document (= RN column) order — see `stringify(_:)`. Parity vectors
/// generated with node live in `BackupChecksumParityTests`.
public enum BackupChecksum {
    /// FNV-1a over UTF-16 code units — RN's `fnv1aHex` hashes
    /// `String.charCodeAt`, a UTF-16 code unit, not a UTF-8 byte, so this
    /// iterates `.utf16` to match.
    public static func fnv1aHex(_ input: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        for unit in input.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x0100_0193
        }
        return String(format: "%08x", hash)
    }

    /// `fnv1aHex(JSON.stringify(rows))`, exactly as RN `archive.ts`.
    public static func checksumFor(_ rows: [BackupRow]) -> String {
        fnv1aHex(stringify(rows))
    }

    /// Emulates `JSON.stringify(rows)` (no indent): keys in the row's own
    /// order, JS string escaping, JS `Number::toString` formatting.
    static func stringify(_ rows: [BackupRow]) -> String {
        "[" + rows.map(stringifyRow).joined(separator: ",") + "]"
    }

    private static func stringifyRow(_ row: BackupRow) -> String {
        let pairs = row.orderedPairs.map { key, value in
            "\"\(escape(key))\":\(stringifyValue(value))"
        }
        return "{" + pairs.joined(separator: ",") + "}"
    }

    private static func stringifyValue(_ value: BackupValue) -> String {
        switch value {
        case .string(let s): return "\"\(escape(s))\""
        case .int(let i): return jsNumberString(Int64: i)
        case .double(let d): return jsNumberString(d)
        case .null: return "null"
        }
    }

    /// JS has one `number` type: a sqlite INTEGER reaches RN as a double,
    /// so anything past 2^53 was already rounded before RN hashed it.
    /// Below that, `String(Int64)` and JS agree digit-for-digit.
    private static func jsNumberString(Int64 i: Int64) -> String {
        if i.magnitude > (1 << 53) { return jsNumberString(Double(i)) }
        return String(i)
    }

    /// ECMAScript `Number::toString(x)` (ES2024 §6.1.6.1.20) for a finite
    /// double, reformatted from Swift's own shortest-round-trip digits
    /// (`Double.description` is Swift-dtoa: the same "shortest digits that
    /// round-trip, closest on ties" V8 uses). Rules, for `k` significant
    /// digits `s` and decimal exponent `n` (x = s × 10^(n−k)):
    ///   k ≤ n ≤ 21      → digits then n−k zeros            (1e16 → "10000000000000000")
    ///   0 < n ≤ 21      → digits with a point after n       (1234.5678)
    ///   −6 < n ≤ 0      → "0." then −n zeros then digits    (0.000001)
    ///   otherwise       → d[.ddd]e±(n−1)                    (1e-7, 1e+21, 1.5e+300)
    /// Integral values therefore print with no `.0` (100.0 → "100"), which
    /// also makes `.double(3)` and `.int(3)` hash identically — the "export
    /// a GRDB REAL, re-import it through JSON" path `BackupImporter`
    /// exercises. `JSON.stringify` writes `null` for NaN/±Infinity and "0"
    /// for −0.
    static func jsNumberString(_ d: Double) -> String {
        guard d.isFinite else { return "null" }
        if d == 0 { return "0" }

        var desc = d.description
        let negative = desc.hasPrefix("-")
        if negative { desc.removeFirst() }

        var mantissa = Substring(desc)
        var exponent = 0
        if let e = desc.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = desc[..<e]
            exponent = Int(desc[desc.index(after: e)...]) ?? 0
        }
        var intPart = mantissa
        var fracPart: Substring = ""
        if let dot = mantissa.firstIndex(of: ".") {
            intPart = mantissa[..<dot]
            fracPart = mantissa[mantissa.index(after: dot)...]
        }

        var digits = String(intPart) + String(fracPart)
        var n = intPart.count + exponent
        while digits.count > 1, digits.hasPrefix("0") { digits.removeFirst(); n -= 1 }
        while digits.count > 1, digits.hasSuffix("0") { digits.removeLast() }
        let k = digits.count

        let out: String
        if k <= n, n <= 21 {
            out = digits + String(repeating: "0", count: n - k)
        } else if 0 < n, n <= 21 {
            out = digits.prefix(n) + "." + digits.dropFirst(n)
        } else if -6 < n, n <= 0 {
            out = "0." + String(repeating: "0", count: -n) + digits
        } else {
            let e = n - 1
            let head = k == 1 ? digits : digits.prefix(1) + "." + digits.dropFirst()
            out = head + "e" + (e < 0 ? "-" : "+") + String(abs(e))
        }
        return negative ? "-" + out : out
    }

    /// JS `QuoteJSONString`: `\b \t \n \f \r \" \\` short forms, every other
    /// code point below 0x20 as lowercase `\u00xx`, everything else (incl.
    /// `/`, non-ASCII and astral characters) verbatim. A Swift `String`
    /// cannot hold a lone surrogate, so that branch of the JS algorithm
    /// never applies.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out
    }
}
