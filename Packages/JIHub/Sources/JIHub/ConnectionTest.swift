import Foundation
import JICore

public enum ConnectionTestResult: Equatable, Sendable { case ok(lastSync: String?), unauthorized, unreachable(String), other(String) }

public enum ConnectionTest {
    /// /health is open (reachability); /ingestion/status needs the bearer (token validity).
    /// SEC-1: must not default to `.shared` — the bearer token and hub JSON would otherwise
    /// land in CFNetwork's on-disk Cache.db on every Test-connection tap. Share HubClient's
    /// ephemeral session so this stays in sync with the same rule there.
    public static func run(_ config: ConnectionConfig, session: URLSession = HubClient.makeDefaultSession()) async -> ConnectionTestResult {
        let client = HubClient(config: config, session: session)
        do { let _: HealthResponse = try await client.get("/health") }
        catch HubError.network(let m) { return .unreachable(m) }
        catch { return .other(humanStatus(for: error)) }
        do { let s: SyncStatus = try await client.get("/api/v1/ingestion/status"); return .ok(lastSync: s.lastSync) }
        catch HubError.unauthorized { return .unauthorized }
        catch { return .other(humanStatus(for: error)) }
    }

    // CODE-5 / PARITY-9: named hub errors are UI contracts — never surface a raw Swift enum dump
    // (e.g. "http(status: 503, detail: Optional(...))") as status text. Map every case to a plain
    // sentence instead.
    private static func humanStatus(for error: Error) -> String {
        switch error {
        case HubError.unauthorized:
            return "Reachable, but the token was rejected."
        case HubError.duplicate:
            return "Hub reported a conflicting record (409)."
        case HubError.yazioAuthExpired:
            return "Hub is up, but the YAZIO connection needs re-authorizing (502)."
        case HubError.http(let status, _) where status == 503:
            return "Hub is up but rejected the request (503). Check HT_API_TOKEN is set on the hub."
        case HubError.http(let status, _):
            return "Hub returned an unexpected error (\(status))."
        case HubError.network(let m):
            return "Unreachable: \(m)"
        case HubError.decoding:
            return "Hub responded, but with data this app didn't understand."
        default:
            return "Something went wrong talking to the hub."
        }
    }
}
