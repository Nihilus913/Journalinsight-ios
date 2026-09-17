import Foundation

/// Pure integrity checksum for a table's row dump — mirrors RN
/// `checksum.ts`'s `fnv1aHex` (FNV-1a, 32-bit), used the same way RN uses
/// it: catching accidental corruption/truncation of an archive file, not a
/// cryptographic boundary (the vault already owns "protect sensitive
/// content" via AES-GCM at the column level; this runs over ciphertext
/// bytes it never needs to understand).
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

    /// Checksum over a table's rows. Unlike RN's `checksumFor`
    /// (`JSON.stringify(rows)`, which preserves each row's original
    /// key-insertion order from JS object literals), this hashes a
    /// SORTED-key canonical JSON: Swift's `BackupRow` (`[String:
    /// BackupValue]`) has no insertion order to begin with, and this
    /// checksum is only ever produced and verified by this app's own
    /// export/import pipeline (never compared byte-for-byte against a
    /// value RN computed), so determinism is what matters, not
    /// reproducing V8's exact key order. `Tests/.../Resources/
    /// fold_archive_v1_redacted.json` was generated with this same
    /// sorted-key scheme so it round-trips.
    public static func checksumFor(_ rows: [BackupRow]) -> String {
        fnv1aHex(canonicalJSON(rows))
    }

    static func canonicalJSON(_ rows: [BackupRow]) -> String {
        "[" + rows.map(canonicalRowJSON).joined(separator: ",") + "]"
    }

    private static func canonicalRowJSON(_ row: BackupRow) -> String {
        let pairs = row.keys.sorted().map { key in
            "\"\(escape(key))\":\(canonicalValueJSON(row[key] ?? .null))"
        }
        return "{" + pairs.joined(separator: ",") + "}"
    }

    private static func canonicalValueJSON(_ value: BackupValue) -> String {
        switch value {
        case .string(let s): return "\"\(escape(s))\""
        case .int(let i): return String(i)
        case .double(let d): return formatDouble(d)
        case .null: return "null"
        }
    }

    /// JS has one `number` type — `JSON.stringify` never distinguishes "3"
    /// from "3.0". Swift's `BackupValue`, in contrast, decodes a
    /// JSON-round-tripped `3` as `.int(3)` (this file's own
    /// `BackupValue.init(from:)` tries `Int64` before `Double`), while a
    /// value read straight off GRDB (a REAL column storing a whole number)
    /// arrives as `.double(3.0)`. Without this, the SAME logical value would
    /// checksum differently depending on whether it came from GRDB or from
    /// a JSON round-trip — exactly the "export, then re-import your own
    /// archive" path `BackupImporter` exercises. Stripping a whole-number
    /// double's trailing `.0` (mirroring `String(3.0) === "3"` in JS) makes
    /// `.double(3.0)` and `.int(3)` checksum identically.
    private static func formatDouble(_ d: Double) -> String {
        if d.isFinite, d == d.rounded(), abs(d) < 1e15 {
            return String(Int64(d))
        }
        return String(d)
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
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
