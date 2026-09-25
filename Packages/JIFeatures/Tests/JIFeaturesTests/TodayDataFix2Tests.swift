import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-FIX2 L5 (DEV-01, DEV-02, DEV-03): Today's HRV card, Sleep ring and sync chip bind to what the
/// hub serves on 2026-09-25 (`/vitals/recovery` `hrv_rmssd_ms` 20.68, `/vitals/sleep-summary`
/// `score_computed` 89, `/ingestion/status` `last_sync`) plus the app's own uploader record.
nonisolated struct Fix2HubStub: HealthDataProvider, SleepSummaryProviding {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    var days: [RecoveryDay]
    var summary: SleepSummary?
    var lastSync: String? = "2026-09-25 10:02:23.725876+02:00"
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { days }
    func syncStatus() async throws -> SyncStatus { SyncStatus(lastSync: lastSync) }
    func sleepSummary() async throws -> SleepSummary {
        guard let summary else { throw HubError.network("simulated") }
        return summary
    }
}

/// The same hub without the sleep-summary seam (a provider that cannot serve it).
nonisolated struct Fix2NoSummaryStub: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    var days: [RecoveryDay]
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { days }
    func syncStatus() async throws -> SyncStatus { throw HubError.network("simulated") }
}

@MainActor
struct TodayDataFix2Tests {
    /// 2026-09-25 10:51 UTC (12:51 CEST, the device regression screenshot).
    static let now = ISO8601DateFormatter().date(from: "2026-09-25T10:51:00Z")!

    /// `/vitals/recovery` 2026-09-25 as served (shape of `vitals_recovery_window_days_28.json`).
    static let hubDays: [RecoveryDay] = [
        RecoveryDay(date: "2026-09-25", sleepScore: 69, sleepDurationSec: 30895, rhrBpm: 81, acwr: 0, hrvWeeklyAvg: 27, hrvRmssdMs: 20.68),
        RecoveryDay(date: "2026-09-24", sleepScore: 79, sleepDurationSec: 26641, rhrBpm: 82, acwr: 0, hrvWeeklyAvg: 28, hrvRmssdMs: 20.71),
    ]
    static let summary = SleepSummary(scoreComputed: 89, scoreComputedDate: "2026-09-25", scoreComputedSource: "AppleHealth",
                                      lastNightDate: "2026-09-25", lastNightDurationSec: 30895, lastNightSource: "AppleHealth")

    private func vm(_ provider: any HealthDataProvider, uploads: UserDefaults? = nil) throws -> TodayViewModel {
        TodayViewModel(provider: provider, cache: OfflineCache(db: try AppDatabase.inMemory()),
                       now: { Self.now }, uploadRecord: uploads)
    }

    private func scratchDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "fix2-l5.\(name)")!
        d.removePersistentDomain(forName: "fix2-l5.\(name)")
        return d
    }

    // MARK: DEV-01

    @Test func hrvCardIsLastNightsRmssdDated() async throws {
        let model = try vm(Fix2HubStub(days: Self.hubDays, summary: Self.summary))
        await model.load()
        let hrv = try #require(model.kpiReading(.hrv))
        #expect(hrv.value == 20.68)
        #expect(hrv.date == "2026-09-25")
        #expect(model.chips.first { $0.id == "hrv" }?.value == 20.68)
        #expect(model.chips.first { $0.id == "hrv" }?.asOf == nil)
    }

    @Test func hrvCardNamesAnOlderNight() async throws {
        var days = Self.hubDays
        days[0].hrvRmssdMs = nil
        let model = try vm(Fix2HubStub(days: days, summary: Self.summary))
        await model.load()
        let hrv = try #require(model.kpiReading(.hrv))
        #expect(hrv.value == 20.71)
        #expect(hrv.date == "2026-09-24")
    }

    @Test func hrvCardNeverShowsTheSevenDayMix() async throws {
        let days = Self.hubDays.map { var d = $0; d.hrvRmssdMs = nil; return d }
        let model = try vm(Fix2HubStub(days: days, summary: Self.summary))
        await model.load()
        #expect(model.kpiReading(.hrv) == nil)
    }

    // MARK: DEV-02

    @Test func sleepRingIsTheHubSleepSummaryScore() async throws {
        let model = try vm(Fix2HubStub(days: Self.hubDays, summary: Self.summary))
        await model.load()
        #expect(model.chips.first { $0.id == "sleep" }?.value == 89)
        #expect(model.kpiReading(.sleep)?.value == 89)
        #expect(model.sleepSummary?.scoreComputed == 89)
    }

    @Test func sleepRingFallsBackToRecoveryWithoutTheSummary() async throws {
        let model = try vm(Fix2NoSummaryStub(days: Self.hubDays))
        await model.load()
        #expect(model.chips.first { $0.id == "sleep" }?.value == 69)
    }

    @Test func aStaleSummaryScoreIsNotLastNight() async throws {
        var old = Self.summary
        old.scoreComputedDate = "2026-09-20"
        let days = Self.hubDays.map { var d = $0; d.sleepScore = nil; return d }
        let model = try vm(Fix2HubStub(days: days, summary: old))
        await model.load()
        #expect(model.chips.first { $0.id == "sleep" }?.value == nil)
    }

    // MARK: DEV-03

    @Test func syncChipIsTheNewerOfHubSyncAndUpload() async throws {
        let uploads = scratchDefaults("newer-upload")
        uploads.set("2026-09-25T10:51:00Z", forKey: "hk.upload.lastSuccess")
        let model = try vm(Fix2HubStub(days: Self.hubDays, summary: Self.summary), uploads: uploads)
        await model.load()
        #expect(model.syncedAt == ISO8601DateFormatter().date(from: "2026-09-25T10:51:00Z"))
    }

    @Test func syncChipIsTheHubSyncWhenItIsNewer() async throws {
        let uploads = scratchDefaults("older-upload")
        uploads.set("2026-09-24T17:23:00Z", forKey: "hk.upload.lastSuccess")
        let model = try vm(Fix2HubStub(days: Self.hubDays, summary: Self.summary), uploads: uploads)
        await model.load()
        let hub = ISO8601DateFormatter().date(from: "2026-09-25T08:02:23Z")!.addingTimeInterval(0.725876)
        let synced = try #require(model.syncedAt)
        #expect(abs(synced.timeIntervalSince(hub)) < 0.01)
    }

    @Test func syncChipIsNilWhenNeitherIsKnown() async throws {
        let model = try vm(Fix2NoSummaryStub(days: Self.hubDays), uploads: scratchDefaults("none"))
        await model.load()
        #expect(model.syncedAt == nil)
    }

    @Test func hubSyncTimestampParses() {
        #expect(parseHubTimestamp("2026-09-25 10:02:23.725876+02:00") != nil)
        #expect(parseHubTimestamp("2026-09-25T08:02:23Z") == ISO8601DateFormatter().date(from: "2026-09-25T08:02:23Z"))
        #expect(parseHubTimestamp(nil) == nil)
        #expect(parseHubTimestamp("garbage") == nil)
    }
}
