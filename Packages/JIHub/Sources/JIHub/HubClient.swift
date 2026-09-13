import Foundation
import JICore

public struct HubClient: Sendable {
    public let config: ConnectionConfig
    private let session: URLSession
    public init(config: ConnectionConfig, session: URLSession = .shared) { self.config = config; self.session = session }

    public func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(url: config.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw HubError.network(error.localizedDescription) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSON.decoder.decode([String: String].self, from: data))?["detail"]
            throw HubError.from(status: status, detail: detail)
        }
        do { return try JSON.decoder.decode(T.self, from: data) } catch { throw HubError.decoding("\(path): \(error)") }
    }
}
