import Foundation

/// W-TGT L1 — a generic JSON tree. Used to hand `HubClient.send` (plain `JSONEncoder()`) a body
/// that was already key-converted by `JSON.encoder` (`.convertToSnakeCase`): encode the typed
/// value with `JSON.encoder`, decode it into a `JSONValue`, send that. Whole numbers stay `int`
/// so pydantic `StrictInt` fields (e.g. `hr_cap_bpm`) accept them.
public nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// `value` encoded with `JSON.encoder` (snake_case keys), as a tree.
    public static func snakeCased<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSON.encoder.encode(value))
    }
}
