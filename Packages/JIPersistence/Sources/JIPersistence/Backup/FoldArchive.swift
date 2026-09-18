import Foundation

/// One JSON scalar as it appears in a raw `SELECT *` row dump — mirrors RN
/// dump.ts's `Record<string, unknown>` (sqlite has only TEXT/INTEGER/REAL/
/// NULL affinities, never a nested object/array column).
public enum BackupValue: Sendable, Equatable, Codable {
    case string(String)
    case int(Int64)
    case double(Double)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported BackupValue")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .null: try c.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

/// One `SELECT *` row, keys in DOCUMENT order. RN's `checksumFor` is
/// `fnv1aHex(JSON.stringify(rows))` over objects expo-sqlite built column-
/// by-column, so the hashed key order IS the table's column order (JS
/// object insertion order; no RN backup table has an array-index-like
/// column name, which V8 would otherwise hoist first). A plain
/// `[String: BackupValue]` forgets that order, so this keeps it: the
/// subscript/literal surface matches a dictionary (every W4 call site
/// compiles unchanged), assigning an existing key keeps its position, and
/// a new key appends.
///
/// `Codable` is kept for API completeness only: neither `JSONEncoder`
/// (keyed output order) nor `JSONDecoder` (`allKeys`) is document-ordered
/// on the macOS toolchain (both verified 2026-09-17), so anything that must
/// checksum-match a Fold archive goes through `FoldArchive.decodeOrdered`
/// / `FoldArchive.encodeOrdered` instead.
public struct BackupRow: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    public private(set) var keys: [String] = []
    private var storage: [String: BackupValue] = [:]

    public init() {}

    public init(dictionaryLiteral elements: (String, BackupValue)...) {
        for (k, v) in elements { self[k] = v }
    }

    public init(_ pairs: [(String, BackupValue)]) {
        for (k, v) in pairs { self[k] = v }
    }

    public subscript(key: String) -> BackupValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    public var isEmpty: Bool { keys.isEmpty }
    public var count: Int { keys.count }

    /// `(key, value)` pairs in document order — the order `BackupChecksum` hashes.
    public var orderedPairs: [(key: String, value: BackupValue)] {
        keys.map { ($0, storage[$0]!) }
    }

    /// Order-sensitive, like the checksum: the same columns in a different
    /// order are a different row.
    public static func == (lhs: BackupRow, rhs: BackupRow) -> Bool {
        lhs.keys == rhs.keys && lhs.storage == rhs.storage
    }
}

extension BackupRow: Codable {
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        self.init()
        for key in c.allKeys {
            self[key.stringValue] = try c.decode(BackupValue.self, forKey: key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        for (k, v) in orderedPairs {
            try c.encode(v, forKey: DynamicKey(stringValue: k))
        }
    }
}

/// One table's dump inside an archive — mirrors RN `archive.ts`'s
/// `BackupTableDump`. `file` is carried through for fidelity with a real
/// Fold archive (which spans several physical sqlite files) but is
/// otherwise unused here: every W4 table lives in the single `AppDatabase`
/// pool.
public struct BackupTableDump: Sendable, Equatable, Codable {
    public var file: String
    public var table: String
    public var rowCount: Int
    public var checksum: String
    public var rows: [BackupRow]

    public init(file: String, table: String, rowCount: Int, checksum: String, rows: [BackupRow]) {
        self.file = file
        self.table = table
        self.rowCount = rowCount
        self.checksum = checksum
        self.rows = rows
    }
}

/// Mirrors RN `vaultKeyWrap.ts`'s `WrappedVaultKey` — the archive's optional
/// carried vault key, wrapped under a passphrase at export time.
public struct FoldWrappedVaultKeyDTO: Sendable, Equatable, Codable {
    public var version: Int
    public var saltHex: String
    public var ivHex: String
    public var iterations: Int
    public var ciphertextB64: String
    public var macHex: String

    public init(version: Int, saltHex: String, ivHex: String, iterations: Int, ciphertextB64: String, macHex: String) {
        self.version = version
        self.saltHex = saltHex
        self.ivHex = ivHex
        self.iterations = iterations
        self.ciphertextB64 = ciphertextB64
        self.macHex = macHex
    }
}

/// The archive's top-level shape — mirrors RN `archive.ts`'s `BackupArchive`.
/// `challengesCache` is decoded/preserved (so a real Fold archive round-trips
/// through `parse -> reserialize` losslessly) but W4 has no `challenges_mirror`
/// table yet, so it is never written back to GRDB (see `BackupTables.notYetMigrated`).
public struct FoldArchive: Sendable, Equatable, Codable {
    public static let format = "healthtraining-mobile-backup"
    public static let schemaVersion = 1

    public var format: String
    public var schemaVersion: Int
    public var appVersion: String
    public var exportedAt: String
    public var tables: [BackupTableDump]
    public var challengesCache: BackupChallengesCacheDump?
    public var vaultKey: FoldWrappedVaultKeyDTO?

    public init(
        format: String = FoldArchive.format,
        schemaVersion: Int = FoldArchive.schemaVersion,
        appVersion: String,
        exportedAt: String,
        tables: [BackupTableDump],
        challengesCache: BackupChallengesCacheDump? = nil,
        vaultKey: FoldWrappedVaultKeyDTO? = nil
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.tables = tables
        self.challengesCache = challengesCache
        self.vaultKey = vaultKey
    }
}

/// Mirrors RN dump.ts's `ChallengesCacheDump` — a single best-effort cache
/// row, carried but never restored by W4 (no `challenges_mirror` table yet).
public struct BackupChallengesCacheDump: Sendable, Equatable, Codable {
    public var key: String
    public var payload: BackupJSON
    public var fetchedAt: String

    public init(key: String, payload: BackupJSON, fetchedAt: String) {
        self.key = key
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

/// A minimal untyped-JSON box, used only for `challengesCache.payload`
/// (an opaque server blob this app never inspects, only carries through).
public indirect enum BackupJSON: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: BackupJSON])
    case array([BackupJSON])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([BackupJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: BackupJSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported BackupJSON")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - Order-preserving encode

extension FoldArchive {
    /// Serializes with every row's keys in their `BackupRow` order — the
    /// order `BackupChecksum` hashed at export — pretty-printed with two
    /// spaces like RN's `JSON.stringify(archive, null, 2)`. Top-level key
    /// order mirrors RN `archive.ts`'s `BackupArchive` literal.
    public func encodeOrdered() -> Data {
        Data(orderedJSON.serialized(indent: 2).utf8)
    }

    var orderedJSON: OrderedJSON {
        var pairs: [(String, OrderedJSON)] = [
            ("format", .string(format)),
            ("schemaVersion", .number(String(schemaVersion))),
            ("appVersion", .string(appVersion)),
            ("exportedAt", .string(exportedAt)),
            ("tables", .array(tables.map(\.orderedJSON))),
        ]
        if let challengesCache {
            pairs.append(("challengesCache", .object([
                ("key", .string(challengesCache.key)),
                ("payload", challengesCache.payload.orderedJSON),
                ("fetchedAt", .string(challengesCache.fetchedAt)),
            ])))
        }
        if let vaultKey {
            pairs.append(("vaultKey", .object([
                ("version", .number(String(vaultKey.version))),
                ("saltHex", .string(vaultKey.saltHex)),
                ("ivHex", .string(vaultKey.ivHex)),
                ("iterations", .number(String(vaultKey.iterations))),
                ("ciphertextB64", .string(vaultKey.ciphertextB64)),
                ("macHex", .string(vaultKey.macHex)),
            ])))
        }
        return .object(pairs)
    }
}

extension BackupTableDump {
    var orderedJSON: OrderedJSON {
        .object([
            ("file", .string(file)),
            ("table", .string(table)),
            ("rowCount", .number(String(rowCount))),
            ("checksum", .string(checksum)),
            ("rows", .array(rows.map(\.orderedJSON))),
        ])
    }
}

extension BackupRow {
    var orderedJSON: OrderedJSON {
        .object(orderedPairs.map { ($0.key, $0.value.orderedJSON) })
    }
}

extension BackupValue {
    /// A finite double is written with Swift's own shortest repr (`3.0`,
    /// `1e-07` — both valid JSON), so a re-import decodes it back to
    /// `.double` and the INTEGER/REAL distinction survives the round trip;
    /// the checksum is unaffected because `BackupChecksum` formats both the
    /// same way. Non-finite → `null`, as `JSON.stringify` does.
    var orderedJSON: OrderedJSON {
        switch self {
        case .string(let s): return .string(s)
        case .int(let i): return .number(String(i))
        case .double(let d): return d.isFinite ? .number(d.description) : .null
        case .null: return .null
        }
    }
}

extension BackupJSON {
    var orderedJSON: OrderedJSON {
        switch self {
        case .string(let s): return .string(s)
        case .number(let d): return d.isFinite ? .number(d.description) : .null
        case .bool(let b): return .bool(b)
        case .null: return .null
        case .array(let a): return .array(a.map(\.orderedJSON))
        case .object(let o): return .object(o.keys.sorted().map { ($0, o[$0]!.orderedJSON) })
        }
    }
}

extension OrderedJSON {
    /// Pretty-printed JSON text (`indent` spaces per level; 0 = compact).
    func serialized(indent: Int) -> String {
        var out = ""
        write(into: &out, indent: indent, depth: 0)
        return out
    }

    private func write(into out: inout String, indent: Int, depth: Int) {
        let pad = String(repeating: " ", count: indent * (depth + 1))
        let closePad = String(repeating: " ", count: indent * depth)
        let newline = indent > 0 ? "\n" : ""
        let colon = indent > 0 ? ": " : ":"
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let literal): out += literal
        case .string(let s): out += "\"" + BackupChecksum.escape(s) + "\""
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[" + newline
            for (i, item) in items.enumerated() {
                out += pad
                item.write(into: &out, indent: indent, depth: depth + 1)
                out += (i == items.count - 1 ? "" : ",") + newline
            }
            out += closePad + "]"
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{" + newline
            for (i, (key, value)) in pairs.enumerated() {
                out += pad + "\"" + BackupChecksum.escape(key) + "\"" + colon
                value.write(into: &out, indent: indent, depth: depth + 1)
                out += (i == pairs.count - 1 ? "" : ",") + newline
            }
            out += closePad + "}"
        }
    }
}

// MARK: - Order-preserving decode

/// The one error the ordered path throws — `BackupImporter.parse` maps every
/// case to `.invalidJSON`, exactly as it did for a `JSONDecoder` failure.
public struct FoldArchiveDecodeError: Error, Equatable, Sendable {
    public let reason: String
}

extension FoldArchive {
    /// Decodes an archive with every row's keys in DOCUMENT order (the order
    /// RN hashed). This is the ONLY decode path whose rows checksum-match a
    /// real Fold archive; `JSONDecoder` loses the order.
    public static func decodeOrdered(_ data: Data) throws -> FoldArchive {
        try FoldArchive(orderedJSON: try OrderedJSON.parse(data))
    }

    init(orderedJSON root: OrderedJSON) throws {
        let format = try root.requiredString("format")
        let schemaVersion = try root.requiredInt("schemaVersion")
        let appVersion = try root.requiredString("appVersion")
        let exportedAt = try root.requiredString("exportedAt")
        guard case .array(let tableNodes)? = root["tables"] else {
            throw FoldArchiveDecodeError(reason: "tables: expected array")
        }
        let tables = try tableNodes.map(BackupTableDump.init(orderedJSON:))

        var challengesCache: BackupChallengesCacheDump?
        if let node = root["challengesCache"], node != .null {
            challengesCache = BackupChallengesCacheDump(
                key: try node.requiredString("key"),
                payload: try (node["payload"] ?? .null).backupJSON(),
                fetchedAt: try node.requiredString("fetchedAt")
            )
        }
        var vaultKey: FoldWrappedVaultKeyDTO?
        if let node = root["vaultKey"], node != .null {
            vaultKey = FoldWrappedVaultKeyDTO(
                version: try node.requiredInt("version"),
                saltHex: try node.requiredString("saltHex"),
                ivHex: try node.requiredString("ivHex"),
                iterations: try node.requiredInt("iterations"),
                ciphertextB64: try node.requiredString("ciphertextB64"),
                macHex: try node.requiredString("macHex")
            )
        }
        self.init(
            format: format, schemaVersion: schemaVersion, appVersion: appVersion, exportedAt: exportedAt,
            tables: tables, challengesCache: challengesCache, vaultKey: vaultKey
        )
    }
}

extension BackupTableDump {
    init(orderedJSON node: OrderedJSON) throws {
        guard case .array(let rowNodes)? = node["rows"] else {
            throw FoldArchiveDecodeError(reason: "rows: expected array")
        }
        self.init(
            file: try node.requiredString("file"),
            table: try node.requiredString("table"),
            rowCount: try node.requiredInt("rowCount"),
            checksum: try node.requiredString("checksum"),
            rows: try rowNodes.map(BackupRow.init(orderedJSON:))
        )
    }
}

extension BackupRow {
    init(orderedJSON node: OrderedJSON) throws {
        guard case .object(let pairs) = node else {
            throw FoldArchiveDecodeError(reason: "row: expected object")
        }
        self.init()
        for (key, value) in pairs {
            self[key] = try value.backupValue()
        }
    }
}

extension OrderedJSON {
    func backupValue() throws -> BackupValue {
        switch self {
        case .null: return .null
        case .string(let s): return .string(s)
        case .number(let literal):
            // A JSON integer literal (no fraction, no exponent) that fits Int64
            // is `.int`, mirroring `BackupValue.init(from:)`'s Int64-before-Double.
            if !literal.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }), let i = Int64(literal) {
                return .int(i)
            }
            guard let d = Double(literal) else { throw FoldArchiveDecodeError(reason: "number: \(literal)") }
            return .double(d)
        case .bool, .array, .object:
            throw FoldArchiveDecodeError(reason: "row value: expected scalar")
        }
    }

    func backupJSON() throws -> BackupJSON {
        switch self {
        case .null: return .null
        case .bool(let b): return .bool(b)
        case .string(let s): return .string(s)
        case .number(let literal):
            guard let d = Double(literal) else { throw FoldArchiveDecodeError(reason: "number: \(literal)") }
            return .number(d)
        case .array(let items): return .array(try items.map { try $0.backupJSON() })
        case .object(let pairs):
            var out: [String: BackupJSON] = [:]
            for (k, v) in pairs { out[k] = try v.backupJSON() }
            return .object(out)
        }
    }

    func requiredString(_ key: String) throws -> String {
        guard case .string(let s)? = self[key] else { throw FoldArchiveDecodeError(reason: "\(key): expected string") }
        return s
    }

    func requiredInt(_ key: String) throws -> Int {
        guard case .number(let literal)? = self[key], let i = Int(literal) else {
            throw FoldArchiveDecodeError(reason: "\(key): expected integer")
        }
        return i
    }
}

/// A small, order-preserving JSON scanner: objects keep their pairs in
/// document order and numbers keep their literal text. It exists because
/// Foundation's `JSONDecoder` has no ordered keyed container, and the Fold
/// archive checksum is order-sensitive. Full RFC 8259 syntax, UTF-8 input,
/// `\u` escapes including surrogate pairs; not tuned for speed (an archive
/// is a few hundred KB at most).
enum OrderedJSON: Equatable {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// The literal as written (`1e+21`, `-0.25`, `42`), converted lazily.
    case number(String)
    case bool(Bool)
    case null

    subscript(key: String) -> OrderedJSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.0 == key }?.1
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    static func parse(_ data: Data) throws -> OrderedJSON {
        var scanner = Scanner(bytes: Array(data))
        scanner.skipWhitespace()
        let value = try scanner.parseValue()
        scanner.skipWhitespace()
        guard scanner.atEnd else { throw FoldArchiveDecodeError(reason: "trailing characters at \(scanner.index)") }
        return value
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { index >= bytes.count }

        func fail(_ what: String) -> FoldArchiveDecodeError {
            FoldArchiveDecodeError(reason: "\(what) at byte \(index)")
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func expect(_ byte: UInt8) throws {
            guard index < bytes.count, bytes[index] == byte else {
                throw fail("expected '\(Character(UnicodeScalar(byte)))'")
            }
            index += 1
        }

        mutating func parseValue() throws -> OrderedJSON {
            guard index < bytes.count else { throw fail("unexpected end") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try parseObject()
            case UInt8(ascii: "["): return try parseArray()
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try expectLiteral("true"); return .bool(true)
            case UInt8(ascii: "f"): try expectLiteral("false"); return .bool(false)
            case UInt8(ascii: "n"): try expectLiteral("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try parseNumber())
            default: throw fail("unexpected character")
            }
        }

        mutating func expectLiteral(_ literal: String) throws {
            let expected = Array(literal.utf8)
            guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else {
                throw fail("expected \(literal)")
            }
            index += expected.count
        }

        mutating func parseObject() throws -> OrderedJSON {
            try expect(UInt8(ascii: "{"))
            var pairs: [(String, OrderedJSON)] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                let key = try parseString()
                skipWhitespace()
                try expect(UInt8(ascii: ":"))
                skipWhitespace()
                let value = try parseValue()
                pairs.append((key, value))
                skipWhitespace()
                guard index < bytes.count else { throw fail("unterminated object") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
                throw fail("expected ',' or '}'")
            }
        }

        mutating func parseArray() throws -> OrderedJSON {
            try expect(UInt8(ascii: "["))
            var items: [OrderedJSON] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try parseValue())
                skipWhitespace()
                guard index < bytes.count else { throw fail("unterminated array") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw fail("expected ',' or ']'")
            }
        }

        mutating func parseNumber() throws -> String {
            let start = index
            if bytes[index] == UInt8(ascii: "-") { index += 1 }
            func digits() -> Int {
                let s = index
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
                return index - s
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "0") {
                index += 1   // a leading zero stands alone: `01` is not JSON
            } else {
                guard digits() > 0 else { throw fail("expected digit") }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard digits() > 0 else { throw fail("expected fraction digit") }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard digits() > 0 else { throw fail("expected exponent digit") }
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        mutating func parseString() throws -> String {
            try expect(UInt8(ascii: "\""))
            var out: [UInt8] = []
            while true {
                guard index < bytes.count else { throw fail("unterminated string") }
                let b = bytes[index]
                index += 1
                switch b {
                case UInt8(ascii: "\""):
                    return String(decoding: out, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    guard index < bytes.count else { throw fail("unterminated escape") }
                    let e = bytes[index]
                    index += 1
                    switch e {
                    case UInt8(ascii: "\""): out.append(0x22)
                    case UInt8(ascii: "\\"): out.append(0x5C)
                    case UInt8(ascii: "/"): out.append(0x2F)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        var unit = try parseHex4()
                        if (0xD800...0xDBFF).contains(unit) {
                            // High surrogate: must be followed by `\uDC00`–`\uDFFF`.
                            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                                throw fail("lone high surrogate")
                            }
                            index += 2
                            let low = try parseHex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw fail("invalid low surrogate") }
                            unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        } else if (0xDC00...0xDFFF).contains(unit) {
                            throw fail("lone low surrogate")
                        }
                        guard let scalar = UnicodeScalar(unit) else { throw fail("invalid scalar") }
                        out.append(contentsOf: Array(String(Character(scalar)).utf8))
                    default:
                        throw fail("invalid escape")
                    }
                case 0x00...0x1F:
                    throw fail("control character in string")
                default:
                    out.append(b)
                }
            }
        }

        mutating func parseHex4() throws -> UInt32 {
            guard index + 4 <= bytes.count else { throw fail("short \\u escape") }
            let text = String(decoding: bytes[index..<index + 4], as: UTF8.self)
            guard let value = UInt32(text, radix: 16) else { throw fail("invalid \\u escape") }
            index += 4
            return value
        }
    }
}
