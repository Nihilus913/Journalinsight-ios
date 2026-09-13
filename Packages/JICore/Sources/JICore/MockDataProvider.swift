import Foundation

/// Previews + tests only. Serves the synced hub-contract fixtures. NEVER the app default (spec §4.2).
public struct MockDataProvider: HealthDataProvider {
    public let capabilities: DataCapability = .hubAll
    public init() {}

    private func load<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/hub-contract")
        else { throw HubError.decoding("missing fixture \(name)") }
        return try JSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }
    public func health() async throws -> HealthResponse { try load("health", as: HealthResponse.self) }
    public func gate(windowDays: Int) async throws -> GateResponse { try load("planning_gate", as: GateResponse.self) }
    public func morning() async throws -> MorningResponse { try load("planning_morning", as: MorningResponse.self) }
    public func morningVerdict(date: String) async throws -> MorningVerdict { try load("planning_morning_verdict", as: MorningVerdict.self) }
    public func recovery(windowDays: Int) async throws -> [RecoveryDay] { try load("vitals_recovery", as: RecoveryReport.self).days }
    public func syncStatus() async throws -> SyncStatus { try load("ingestion_status", as: SyncStatus.self) }
}
