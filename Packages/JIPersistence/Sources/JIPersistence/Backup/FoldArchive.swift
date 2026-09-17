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

public typealias BackupRow = [String: BackupValue]

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
