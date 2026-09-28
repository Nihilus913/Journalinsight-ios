import Foundation
import Testing
import JICore
import JIHealthKit
@testable import JIFeatures

// W-DATA L1 — R2 (DEV-12) + R3 (DEV-14).

// MARK: - R2: "Connect" once decided opens Health settings (iOS never re-prompts a decided type)

@Test @MainActor func connectWhenUndecidedRequestsAccess() async {
    var requested = 0, opened = 0
    let vm = HealthPermissionViewModel(permission: .notDetermined,
                                       requestPermission: { requested += 1; return .granted },
                                       openHealthSettings: { opened += 1 })
    #expect(vm.isDecided == false)
    #expect(vm.connectLabel == "Connect Apple Health")
    await vm.connect()
    #expect(requested == 1 && opened == 0)
    #expect(vm.isDecided)
    #expect(vm.connectLabel == "Open Health settings")
}

@Test @MainActor func connectWhenDecidedOpensHealthSettingsNotTheDeadSheet() async {
    var requested = 0, opened = 0
    let vm = HealthPermissionViewModel(permission: .granted,
                                       requestPermission: { requested += 1; return .granted },
                                       openHealthSettings: { opened += 1 })
    await vm.connect()
    #expect(requested == 0 && opened == 1)
}

// MARK: - R2: arrival is proof of a read grant — never "Declined" once uploaded

@Test @MainActor func arrivalAdoptsGrantedEvenOverDenied() {
    let vm = HealthPermissionViewModel(permission: .denied, requestPermission: { .denied }, openHealthSettings: {})
    vm.adoptArrival(nil)
    #expect(vm.permission == .denied)
    vm.adoptArrival(Date())
    #expect(vm.permission == .granted)
    #expect(!HealthPermissionViewModel.statusCopy(for: vm.permission).contains("declined"))
}

@Test func readRowsUsePerTypeArrival() {
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_790_208_000 + 9 * 3600)
    let sleep = Date(timeIntervalSince1970: 1_790_208_000 + 6 * 3600)
    let rows = healthReadRowsArrival(capabilities: [.hrvRMSSD],
                                     arrivals: HealthReadArrivals(hrv: nil, sleep: sleep, restingHR: nil), now: now)
    #expect(rows.map(\.title) == ["Overnight HRV", "Sleep", "Resting HR", "Workouts", "Food"])
    #expect(rows[0].status.word == "No data yet")
    #expect(rows[1].status.word.hasPrefix("Connected"))
    #expect(rows[2].status.word == "No data yet")
    #expect(rows[3].status.word == "No data yet" && rows[4].status.word == "No data yet")
    #expect(!rows.contains { $0.status.word == "Declined" })
}

@Test func readArrivalsComeFromThePerTypeRecords() {
    let d = UserDefaults(suiteName: "WDataHealth.\(UUID().uuidString)")!
    d.set("2026-09-27T05:41:00Z", forKey: HealthKitArrival.key(for: HKReadKind.restingHeartRate.sampleType!))
    d.set("2026-09-27T05:40:00Z", forKey: HealthKitArrival.key(for: HKReadKind.hrvSDNN.sampleType!))
    let a = healthReadArrivals(d)
    #expect(a.restingHR != nil && a.hrv != nil)
    #expect(a.sleep == nil)
}

// MARK: - R3: Readiness / Sleep score are never "Garmin only" / "not on this source"

@Test func gatedTilesNeverIncludeReadinessOrSleepScore() {
    let labels = healthSourceGatedLabels(capabilities: [.hrvSDNN])
    #expect(labels == ["Body Battery", "HRV (RMSSD)"])
    #expect(healthSourceGatedLabels(capabilities: [.hrvSDNN, .hrvRMSSD]) == ["Body Battery"])
    for tile in healthComputedTiles(sleepScore: nil) where tile.id != "bodyBattery" {
        #expect(!tile.note.localizedCaseInsensitiveContains("garmin"))
    }
}

@Test @MainActor func sleepScoreComesFromTheHubLoaderWhenWired() async {
    let vm = HealthPermissionViewModel(permission: .granted, requestPermission: { .granted },
                                       openHealthSettings: {}, loadSleepScore: { 89 })
    #expect(vm.sleepScore == nil)
    await vm.refreshComputed()
    #expect(vm.sleepScore == 89)
    #expect(healthComputedTiles(sleepScore: vm.sleepScore)[1].value == "89")
    let unwired = HealthPermissionViewModel(permission: .granted, requestPermission: { .granted }, openHealthSettings: {})
    await unwired.refreshComputed()
    #expect(unwired.sleepScore == nil)   // "—", never fabricated
}
