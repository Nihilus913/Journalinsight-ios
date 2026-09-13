import Foundation
import JICore

public struct ConnectionConfig: Codable, Sendable, Equatable {
    public var baseURL: URL
    public var token: String
    public init(baseURL: URL, token: String) { self.baseURL = baseURL; self.token = token }

    // Explicit keys: JSON.decoder's .convertFromSnakeCase turns wire key "base_url" into
    // "baseUrl" (it cannot restore the "URL" acronym casing), which does not match the
    // auto-synthesized CodingKeys.baseURL ("baseURL") and throws keyNotFound. Spelling the
    // raw value as "baseUrl" here matches what the strategy actually produces on decode,
    // while JSON.encoder's .convertToSnakeCase still turns it into "base_url" on encode —
    // verified round-trip via configRoundTripsThroughSecretStore.
    private enum CodingKeys: String, CodingKey {
        case baseURL = "baseUrl"
        case token
    }
}

public struct ConnectionConfigStore: Sendable {
    public static let key = "ht.connection.v1"
    private let secrets: any SecretStore
    public init(secrets: any SecretStore = KeychainStore()) { self.secrets = secrets }
    public func load() throws -> ConnectionConfig? {
        guard let d = try secrets.read(Self.key) else { return nil }
        return try JSON.decoder.decode(ConnectionConfig.self, from: d)
    }
    public func save(_ c: ConnectionConfig) throws { try secrets.write(Self.key, JSON.encoder.encode(c)) }
    public func clear() throws { try secrets.delete(Self.key) }
}
