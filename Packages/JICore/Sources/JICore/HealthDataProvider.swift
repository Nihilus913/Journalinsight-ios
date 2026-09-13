/// The Today slice of the hub contract: the methods every Today-screen tile needs. The remaining
/// 21 hub routes (exercises, energy, nutrition, food log, weigh-in, gate respond, feel, sync
/// trigger/job, goals, kpi targets, challenges, data quality, sleep summary) are added in W3/W4 by
/// the task that first needs each; each addition ships with its own contract-fixture decode test.
public protocol HealthDataProvider: Sendable {
    /// What this provider supplies (spec §4.2) — tiles read the bitmap, never the provider type.
    var capabilities: DataCapability { get }

    /// `GET /health`
    func health() async throws -> HealthResponse

    /// `GET /api/v1/planning/gate?window_days=`
    func gate(windowDays: Int) async throws -> GateResponse

    /// `GET /api/v1/planning/morning`
    func morning() async throws -> MorningResponse

    /// `GET /api/v1/planning/morning-verdict?date=`
    func morningVerdict(date: String) async throws -> MorningVerdict

    /// `GET /api/v1/vitals/recovery?window_days=` → unwrap `.days`
    func recovery(windowDays: Int) async throws -> [RecoveryDay]

    /// `GET /api/v1/ingestion/status`
    func syncStatus() async throws -> SyncStatus
}
