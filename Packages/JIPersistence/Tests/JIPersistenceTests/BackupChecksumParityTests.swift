import Foundation
import Testing
@testable import JIPersistence

/// Node-generated parity vectors (2026-09-17, node v25.8.2): each `rows`
/// string is `JSON.stringify(rows)` and each `checksum` is RN
/// `checksum.ts`'s `fnv1aHex` of that string, copied verbatim. Rows are
/// deliberately unsorted-key, with `null`, ints, doubles across every JS
/// `Number::toString` branch, every short escape, a C0 control, `/`, and
/// non-ASCII including astral (surrogate-pair) characters. Swift must
/// reproduce both the string and the checksum byte-exact. Regenerate with
/// a throwaway node script that inlines `fnv1aHex` (never edit RN).
private let parityVectors: [(rows: String, checksum: String)] = [
    (#"[{"id":1,"name":"training"}]"#, "4d2c80a8"),
    (#"[{"z":"last","a":"first","m":null,"0b":"not-index-like"}]"#, "33447348"),
    (#"[{"id":2,"progress":0.5,"ratio":1e+21,"tiny":1e-7,"whole":3,"hundred":100}]"#, "ec3012e4"),
    (#"[{"text":"line\nbreak\ttab \"quoted\" back\\slash \u0001\u001f \b\f\r end","slash":"a/b"}]"#, "1dc05dde"),
    (#"[{"note":"Grüße 🚀 日本語 — café","emoji":"👨‍👩‍👧"}]"#, "2cba1568"),
    (#"[{"id":-5,"neg":-0.25,"big":9007199254740991,"exp":123456789012345680000,"sixteen":10000000000000000,"micro":0.000001,"submicro":1e-7,"huge":1.5e+300,"tinyd":5e-324}]"#, "dd9e4f9d"),
    (#"[{"id":3,"date":"2026-09-08","ts":"2026-09-08T07:15:00.000Z","text":"htv1:224b2b55c97409c32c78a25232efe679:iGs3uKxX+SQR4y5PycFBIPwC0kAuKNfQ01HQHgYS+Fk=","duration_sec":42,"mood":null,"synced":0}]"#, "0fc5e70d"),
    (#"[{"strength_json":"{\"bench\":{\"weight\":60,\"reps\":8}}","updated_at":"2026-09-10T08:00:00.000Z"}]"#, "bd95982e"),
]

/// All eight vector rows in one `rows` array — `fnv1aHex(JSON.stringify(rows))`.
private let allRowsChecksum = "3361d133"

private func decodeRows(_ json: String) throws -> [BackupRow] {
    guard case .array(let nodes) = try OrderedJSON.parse(Data(json.utf8)) else {
        throw FoldArchiveDecodeError(reason: "vector: expected array")
    }
    return try nodes.map(BackupRow.init(orderedJSON:))
}

@Test func everyNodeVectorChecksumsByteExact() throws {
    for (rows, checksum) in parityVectors {
        let decoded = try decodeRows(rows)
        #expect(BackupChecksum.stringify(decoded) == rows, "stringify drift for \(rows)")
        #expect(BackupChecksum.checksumFor(decoded) == checksum, "checksum drift for \(rows)")
    }
}

@Test func concatenatedVectorRowsChecksumMatchesNode() throws {
    let rows = try parityVectors.flatMap { try decodeRows($0.rows) }
    #expect(rows.count == parityVectors.count)
    #expect(BackupChecksum.checksumFor(rows) == allRowsChecksum)
}

@Test func keyOrderChangesTheChecksumLikeRN() throws {
    let documentOrder: BackupRow = ["z": .string("last"), "a": .string("first"), "m": .null, "0b": .string("not-index-like")]
    let sortedOrder: BackupRow = ["0b": .string("not-index-like"), "a": .string("first"), "m": .null, "z": .string("last")]
    #expect(BackupChecksum.checksumFor([documentOrder]) == "33447348")
    #expect(BackupChecksum.checksumFor([sortedOrder]) != "33447348")
}

/// `[String(n), JSON.stringify(n)]` pairs from node, covering every branch
/// of `Number::toString`.
@Test func jsNumberFormattingMatchesV8() {
    let cases: [(Double, String)] = [
        (0.5, "0.5"), (1e21, "1e+21"), (1e-7, "1e-7"), (3, "3"), (100.0, "100"), (-0.25, "-0.25"),
        (123456789012345680000, "123456789012345680000"), (1e16, "10000000000000000"),
        (0.000001, "0.000001"), (0.0000001, "1e-7"), (1.5e300, "1.5e+300"), (5e-324, "5e-324"),
        (-0.0, "0"), (1234.5678, "1234.5678"), (1e20, "100000000000000000000"), (1e-6, "0.000001"),
        (12345678901234567890, "12345678901234567000"), (0.1, "0.1"), (1.0 / 3.0, "0.3333333333333333"),
        (2.5e-5, "0.000025"), (123e-20, "1.23e-18"),
    ]
    for (value, expected) in cases {
        #expect(BackupChecksum.jsNumberString(value) == expected, "\(value)")
    }
    #expect(BackupChecksum.jsNumberString(.nan) == "null")
    #expect(BackupChecksum.jsNumberString(.infinity) == "null")
}

@Test func intAndIntegralDoubleHashIdentically() {
    let fromJSON: BackupRow = ["id": .int(3), "progress": .int(1)]
    let fromGRDB: BackupRow = ["id": .int(3), "progress": .double(1.0)]
    #expect(BackupChecksum.checksumFor([fromJSON]) == BackupChecksum.checksumFor([fromGRDB]))
    // Past 2^53 a sqlite INTEGER is a rounded JS double in RN.
    #expect(BackupChecksum.stringify([["big": .int(1234567890123456789)]]) == #"[{"big":1234567890123456800}]"#)
}

// MARK: - BackupRow ordering surface

@Test func backupRowKeepsDocumentOrderThroughSubscriptAndLiteral() {
    var row: BackupRow = ["b": .int(1), "a": .int(2)]
    row["c"] = .null
    row["b"] = .string("updated")          // existing key keeps its slot
    #expect(row.keys == ["b", "a", "c"])
    #expect(row["b"] == .string("updated"))
    row["a"] = nil
    #expect(row.keys == ["b", "c"])
    #expect(row.count == 2)
    #expect(!row.isEmpty)
    #expect(BackupRow().isEmpty)
}

@Test func orderedWriterKeepsRowKeysInDocumentOrder() throws {
    let row: BackupRow = ["z": .int(1), "a": .string("x"), "m": .null, "d": .double(3), "e": .double(1e-7)]
    let compact = OrderedJSON.array([row.orderedJSON]).serialized(indent: 0)
    #expect(compact == #"[{"z":1,"a":"x","m":null,"d":3.0,"e":1e-07}]"#)
    // Re-reading the writer's own output keeps the order, the REAL/INTEGER split, and the checksum.
    let back = try decodeRows(compact)
    #expect(back == [row])
    #expect(BackupChecksum.checksumFor(back) == BackupChecksum.checksumFor([row]))
}

@Test func orderedWriterPrettyPrintsLikeRN() {
    let node = OrderedJSON.object([("a", .array([.number("1"), .null])), ("b", .object([])), ("c", .string("q\"\n"))])
    let expected = "{\n  \"a\": [\n    1,\n    null\n  ],\n  \"b\": {},\n  \"c\": \"q\\\"\\n\"\n}"
    #expect(node.serialized(indent: 2) == expected)
}

@Test func orderedScannerRoundTripsEscapesAndSurrogates() throws {
    let rows = try decodeRows(#"[{"s":"\u00e9\ud83d\ude80\/\b\f\n\r\t\"\\","n":-1.5e-3,"i":42,"z":null}]"#)
    #expect(rows.count == 1)
    #expect(rows[0].keys == ["s", "n", "i", "z"])
    #expect(rows[0]["s"] == .string("é🚀/\u{08}\u{0C}\n\r\t\"\\"))
    #expect(rows[0]["n"] == .double(-0.0015))
    #expect(rows[0]["i"] == .int(42))
    #expect(rows[0]["z"] == .null)
}

@Test func orderedScannerRejectsMalformedInput() {
    for bad in ["", "[", #"{"a":1,}"#, #"{"a":tru}"#, #"["\ud800"]"#, "[1] x", "01"] {
        #expect(throws: FoldArchiveDecodeError.self, "\(bad)") { try OrderedJSON.parse(Data(bad.utf8)) }
    }
}
