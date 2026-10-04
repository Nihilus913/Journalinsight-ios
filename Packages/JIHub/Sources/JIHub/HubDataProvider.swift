import JICore

public struct HubDataProvider: HealthDataProvider {
    public let capabilities: DataCapability = .hubAll
    let client: HubClient
    /// B-44 Option B: the on-device verdict laid over `morning()` / `morningVerdict(date:)` (the gate
    /// and Decide read it; the hub keeps computing its own silently). nil = the hub's verdict only.
    public let verdictOverlay: (any MorningVerdictOverlay)?
    public init(client: HubClient, verdictOverlay: (any MorningVerdictOverlay)? = nil) {
        self.client = client
        self.verdictOverlay = verdictOverlay
    }

    /// The same connection without the overlay — the hub's own verdict (shadow log column).
    public var hubOnly: HubDataProvider { HubDataProvider(client: client) }

    public func health() async throws -> HealthResponse { try await client.get("/health") }
    public func gate(windowDays: Int = 28) async throws -> GateResponse {
        try await client.get("/api/v1/planning/gate", query: ["window_days": String(min(windowDays, 365))])
    }
    public func morning() async throws -> MorningResponse {
        let hub: MorningResponse = try await client.get("/api/v1/planning/morning")
        guard let verdictOverlay, let mine = await verdictOverlay.verdict(day: verdictOverlay.todayKey) else { return hub }
        return hub.overlaid(with: mine)
    }
    public func morningVerdict(date: String) async throws -> MorningVerdict {
        if let verdictOverlay, let mine = await verdictOverlay.verdict(day: date) { return mine.asMorningVerdict }
        return try await client.get("/api/v1/planning/morning-verdict", query: ["date": date])
    }
    public func recovery(windowDays: Int = 28) async throws -> [RecoveryDay] {
        let r: RecoveryReport = try await client.get("/api/v1/vitals/recovery", query: ["window_days": String(min(windowDays, 365))])
        return r.days
    }
    public func syncStatus() async throws -> SyncStatus { try await client.get("/api/v1/ingestion/status") }
}
