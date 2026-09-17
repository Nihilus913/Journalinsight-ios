import Foundation
import Testing
import JICore
@testable import JIFeatures

// MARK: - Status copy (three-state honesty, wave card exit criterion)

@Test @MainActor func statusCopyGrantedSaysConnected() {
    #expect(HealthPermissionViewModel.statusCopy(for: .granted) == "Apple Health connected.")
}

@Test @MainActor func statusCopyDeniedNamesTheSettingsPathNotNoData() {
    let copy = HealthPermissionViewModel.statusCopy(for: .denied)
    #expect(copy.contains("Health › Sharing › Apps"))
    #expect(copy.contains("declined"))
    // Denial must never be described as an absence of data (rule 5 / card: "denied ≠ 'no data'").
    #expect(!copy.localizedCaseInsensitiveContains("no data"))
}

@Test @MainActor func statusCopyNotDeterminedInvitesConnecting() {
    let copy = HealthPermissionViewModel.statusCopy(for: .notDetermined)
    #expect(copy.contains("Connect Apple Health"))
    #expect(!copy.localizedCaseInsensitiveContains("no data"))
}

@Test @MainActor func allThreeStatesProduceDistinctCopy() {
    let states: [HKPermission] = [.granted, .denied, .notDetermined]
    let copies = Set(states.map(HealthPermissionViewModel.statusCopy(for:)))
    #expect(copies.count == 3)
}

// MARK: - Connect button → injected closure

@Test @MainActor func connectCallsTheInjectedPermissionRequestAndAdoptsItsResult() async {
    var requested = false
    let vm = HealthPermissionViewModel(permission: .notDetermined, requestPermission: {
        requested = true
        return .granted
    })
    #expect(vm.permission == .notDetermined)

    await vm.connect()

    #expect(requested)
    #expect(vm.permission == .granted)
}

@Test @MainActor func connectAdoptsDeniedWithoutCrashingOrAssumingSuccess() async {
    let vm = HealthPermissionViewModel(permission: .notDetermined, requestPermission: { .denied })
    await vm.connect()
    #expect(vm.permission == .denied)
}

// MARK: - Gated tiles (T2 set: Apple Watch never supplies these four)

@Test @MainActor func garminOnlyCapabilitiesAreGatedWhenNotInTheAppleWatchSet() {
    let vm = HealthPermissionViewModel(appleWatchCapabilities: [.hrvSDNN], requestPermission: { .granted })
    #expect(vm.isGated(.bodyBattery))
    #expect(vm.isGated(.garminSleepScore))
    #expect(vm.isGated(.trainingReadiness))
    #expect(vm.isGated(.hrvRMSSD))
}

@Test @MainActor func hrvSDNNIsNeverGatedForAppleWatch() {
    let vm = HealthPermissionViewModel(appleWatchCapabilities: [.hrvSDNN], requestPermission: { .granted })
    #expect(vm.isGated(.hrvSDNN) == false)
}

@Test @MainActor func hrvRMSSDIsUngatedOnlyWhenExplicitlyIncluded() {
    // Stand-in for "iOS 27 RMSSD type exists" (wave card) — L1 decides when to include it;
    // this VM only reacts to whatever capability set it's given.
    let vm = HealthPermissionViewModel(appleWatchCapabilities: [.hrvSDNN, .hrvRMSSD], requestPermission: { .granted })
    #expect(vm.isGated(.hrvRMSSD) == false)
}
