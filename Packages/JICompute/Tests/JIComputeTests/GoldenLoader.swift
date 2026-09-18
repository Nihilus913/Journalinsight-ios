import Foundation

/// Loads the Python-generated golden fixtures into `@Test(arguments:)` inputs.
///
/// The fixtures under `Resources/golden/` are byte-copies of
/// `HealthTraining/mobile/__tests__/compute/golden/*.golden.json`; HT stays the
/// source of truth and `HealthTraining/scripts/regen_goldens.py` refreshes them.
/// Never edit them here.
///
/// Strictness is the point: a golden file that grows a field the Swift port does
/// not know about must FAIL, not silently pass with the new column ignored.
/// `Decodable` drops unknown keys by default, so every case type declares its
/// `allowedKeys` and `StrictCase` checks the raw key set before decoding.
enum GoldenLoader {
    enum Failure: Error, CustomStringConvertible {
        case missingResource(file: String)
        case missingGroup(file: String, group: String)
        case unknownKeys(file: String, group: String, keys: [String])
        case decode(file: String, group: String, underlying: String)

        var description: String {
            switch self {
            case .missingResource(let file):
                return "golden fixture \(file) is not in the test bundle — check Package.swift resources"
            case .missingGroup(let file, let group):
                return "golden fixture \(file) has no case group \"\(group)\""
            case .unknownKeys(let file, let group, let keys):
                return "golden fixture \(file) group \"\(group)\" has unknown key(s) \(keys.sorted().joined(separator: ", ")) — the Swift port is behind the generator"
            case .decode(let file, let group, let underlying):
                return "golden fixture \(file) group \"\(group)\" failed to decode: \(underlying)"
            }
        }
    }

    static let groupUserInfoKey = CodingUserInfoKey(rawValue: "ji.compute.goldenGroup")!
    static let fileUserInfoKey = CodingUserInfoKey(rawValue: "ji.compute.goldenFile")!

    /// Decode one named case array out of one golden file.
    static func load<Case: GoldenCase>(_ type: Case.Type, file: String, group: String) throws -> [Case] {
        guard let url = Bundle.module.url(forResource: file, withExtension: "json", subdirectory: "Resources/golden") else {
            throw Failure.missingResource(file: file)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.userInfo[groupUserInfoKey] = group
        decoder.userInfo[fileUserInfoKey] = file
        do {
            return try decoder.decode(Group<Case>.self, from: data).cases.map(\.value)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.decode(file: file, group: group, underlying: String(describing: error))
        }
    }

    /// `load` for use in a `@Test(arguments:)` position, where throwing is not
    /// an option. A broken fixture is a build-level defect, so it traps with the
    /// full diagnostic rather than reporting zero cases (which would pass).
    static func require<Case: GoldenCase>(_ type: Case.Type, file: String, group: String) -> [Case] {
        do {
            return try load(type, file: file, group: group)
        } catch {
            fatalError("\(error)")
        }
    }

    /// Wrapper that pulls a single named array out of the file's top-level object.
    private struct Group<Case: GoldenCase>: Decodable {
        let cases: [StrictCase<Case>]

        init(from decoder: Decoder) throws {
            let file = decoder.userInfo[GoldenLoader.fileUserInfoKey] as? String ?? "?"
            let group = decoder.userInfo[GoldenLoader.groupUserInfoKey] as? String ?? "?"
            let container = try decoder.container(keyedBy: AnyKey.self)
            let key = AnyKey(group)
            guard container.contains(key) else { throw Failure.missingGroup(file: file, group: group) }
            cases = try container.decode([StrictCase<Case>].self, forKey: key)
        }
    }
}

/// A golden case that knows exactly which JSON keys it accounts for.
protocol GoldenCase: Decodable, Sendable {
    static var allowedKeys: Set<String> { get }
}

/// Decodes `Case`, but first fails on any JSON key the case type does not claim.
///
/// `container(keyedBy: AnyKey.self)` accepts every string, so `allKeys` here is
/// the real key set of the JSON object — unlike a `CodingKeys`-typed container,
/// which silently reports only the keys it recognises.
struct StrictCase<Case: GoldenCase>: Decodable {
    let value: Case

    init(from decoder: Decoder) throws {
        let file = decoder.userInfo[GoldenLoader.fileUserInfoKey] as? String ?? "?"
        let group = decoder.userInfo[GoldenLoader.groupUserInfoKey] as? String ?? "?"
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let present = Set(raw.allKeys.map(\.stringValue))
        let unknown = present.subtracting(Case.allowedKeys)
        guard unknown.isEmpty else {
            throw GoldenLoader.Failure.unknownKeys(file: file, group: group, keys: Array(unknown))
        }
        value = try Case(from: decoder)
    }
}

/// A `CodingKey` that accepts any name, so a keyed container can report the raw
/// key set of a JSON object.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
