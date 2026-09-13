import Foundation
import JICore

public enum ConnectionTestResult: Equatable, Sendable { case ok(lastSync: String?), unauthorized, unreachable(String), other(String) }

public enum ConnectionTest {
    /// /health is open (reachability); /ingestion/status needs the bearer (token validity).
    public static func run(_ config: ConnectionConfig, session: URLSession = .shared) async -> ConnectionTestResult {
        let client = HubClient(config: config, session: session)
        do { let _: HealthResponse = try await client.get("/health") } catch HubError.network(let m) { return .unreachable(m) } catch { return .other("\(error)") }
        do { let s: SyncStatus = try await client.get("/api/v1/ingestion/status"); return .ok(lastSync: s.lastSync) }
        catch HubError.unauthorized { return .unauthorized }
        catch { return .other("\(error)") }
    }
}
