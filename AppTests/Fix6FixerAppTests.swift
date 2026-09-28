import Foundation
import Testing
import JICore
import JIFeatures
import JIHub
@testable import JournalInsight

/// W-FIX6 fixer: F6-12/F6-12b (Settings + More hub screens built from the hub whatever the data
/// source) and F6-18 (Search before More in the tab bar).
struct Fix6FixerAppTests {
    /// The on-device (T2) data source: a plain `HealthDataProvider`, none of the hub-only protocols.
    private struct OnDevice: HealthDataProvider {
        var capabilities: DataCapability { [.recovery] }
        func health() async throws -> HealthResponse { HealthResponse(status: "ok") }
        func gate(windowDays: Int) async throws -> GateResponse { throw HubError.network("x") }
        func morning() async throws -> MorningResponse { throw HubError.network("x") }
        func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.network("x") }
        func recovery(windowDays: Int) async throws -> [RecoveryDay] { [] }
        func syncStatus() async throws -> SyncStatus { SyncStatus() }
    }

    /// F6-12/F6-12b: data source = Apple Watch, hub connected → Goals, My KPIs, Nutrition and
    /// Energy still get a provider that serves them (the hub), so the rows open.
    @Test func hubScreensReadTheHubWhenTheDataSourceIsAppleWatch() throws {
        let hub = HubDataProvider(client: HubClient(config: ConnectionConfig(baseURL: try #require(URL(string: "http://127.0.0.1:1")), token: "t")))
        let source = RootTabView.hubScreensSource(hub: hub, dataSource: OnDevice())
        #expect(source as? any GoalsSetupProviding != nil)
        #expect(source as? any KpiTargetsProviding != nil)
        #expect(source as? any NutritionProviding != nil)
        #expect(source as? any EnergyProviding != nil)
        #expect(RootTabView.hubScreensSource(hub: nil, dataSource: OnDevice()) is OnDevice)
    }

    /// F6-18: Today · Recovery · Training · Search · More.
    @Test func searchSitsBeforeMore() {
        #expect(RootTab.barOrder == [.today, .recovery, .training, .search, .more])
        #expect(RootTab.leadingTabs + [.search] + RootTab.trailingTabs == RootTab.barOrder)
    }
}
