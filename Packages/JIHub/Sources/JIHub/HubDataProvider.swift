import JICore

public struct HubDataProvider: HealthDataProvider {
    public let capabilities: DataCapability = .hubAll
    let client: HubClient
    public init(client: HubClient) { self.client = client }

    public func health() async throws -> HealthResponse { try await client.get("/health") }
    public func gate(windowDays: Int = 28) async throws -> GateResponse {
        try await client.get("/api/v1/planning/gate", query: ["window_days": String(min(windowDays, 365))])
    }
    public func morning() async throws -> MorningResponse { try await client.get("/api/v1/planning/morning") }
    public func morningVerdict(date: String) async throws -> MorningVerdict {
        try await client.get("/api/v1/planning/morning-verdict", query: ["date": date])
    }
    public func recovery(windowDays: Int = 28) async throws -> [RecoveryDay] {
        let r: RecoveryReport = try await client.get("/api/v1/vitals/recovery", query: ["window_days": String(min(windowDays, 365))])
        return r.days
    }
    public func syncStatus() async throws -> SyncStatus { try await client.get("/api/v1/ingestion/status") }
}
