import Foundation
import JICore

/// `HubDataProvider.client` is `private` and `HubDataProvider.swift` is frozen this wave (Data
/// seam) — `private` is file-scoped in Swift, so this extension (a different file, per the card)
/// cannot reach the instance's own client. This conformance instead re-derives its own `HubClient`
/// from the persisted `ConnectionConfig`, exactly the pattern `ConnectionTest.run` already uses
/// independently of `HubDataProvider`. `trainingSecrets`/`trainingSession` are test-overridable
/// static seams (`nonisolated(unsafe)`, mirroring `StubURLProtocol`'s own process-global
/// test-double convention — guarded by the same `.serialized` test-suite discipline) so
/// `JIHubTests` can stub both without touching the frozen `client` field; production code never
/// sets them, so they stay the real Keychain + `HubClient`'s SEC-1 ephemeral session.
extension HubDataProvider: TrainingProviding {
    nonisolated(unsafe) public static var trainingSecrets: any SecretStore = KeychainStore()
    nonisolated(unsafe) public static var trainingSession: URLSession = HubClient.makeDefaultSession()

    private func trainingConfig() throws -> ConnectionConfig {
        guard let config = try ConnectionConfigStore(secrets: Self.trainingSecrets).load() else {
            throw HubError.network("no connection configured")
        }
        return config
    }

    public func trainingDay(date: String) async throws -> TrainingDayDetail {
        let config = try trainingConfig()
        return try await HubClient(config: config, session: Self.trainingSession).get("/api/v1/training/day/\(date)")
    }

    public func exercises() async throws -> [Exercise] {
        let config = try trainingConfig()
        return try await HubClient(config: config, session: Self.trainingSession).get("/api/v1/planning/exercises")
    }

    public func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        let config = try trainingConfig()
        return try await Self.patch("/api/v1/planning/exercises/\(exerciseId)", body: patch, config: config)
    }

    /// `HubClient` exposes only `get`/`post` (frozen) — a minimal PATCH mirroring `HubClient.post`'s
    /// own request/error/decode shape exactly (same SEC-1 ephemeral-session discipline, same
    /// `JSONEncoder()` — not `JSON.encoder` — for the outgoing body, same `JSON.decoder` /
    /// `HubError.from` on the way back), since `HubClient.swift` may not be edited this wave.
    private static func patch<B: Encodable, T: Decodable>(_ path: String, body: B, config: ConnectionConfig) async throws -> T {
        var req = URLRequest(url: config.baseURL.appending(path: path))
        req.httpMethod = "PATCH"
        req.timeoutInterval = 15
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { req.httpBody = try JSONEncoder().encode(body) } catch { throw HubError.decoding("\(path): encode \(error)") }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.trainingSession.data(for: req) } catch { throw HubError.network(error.localizedDescription) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSON.decoder.decode([String: String].self, from: data))?["detail"]
            throw HubError.from(status: status, detail: detail)
        }
        do { return try JSON.decoder.decode(T.self, from: data) } catch { throw HubError.decoding("\(path): \(error)") }
    }
}
