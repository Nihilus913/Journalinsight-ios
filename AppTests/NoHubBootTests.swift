import Foundation
import Testing
import JICore
import JIHub
import JIHealthKit
import JIFeatures
@testable import JournalInsight

/// W-OFFLINE2 OFF2-1 (B-50 slice 2): with no `ConnectionConfig` the app boots on the on-device
/// `HealthKitProvider` (Today + Recovery render the on-device verdict and HealthKit values) instead
/// of a full-screen "Connect to your hub" replacement; a saved config keeps the hub path as before.
@MainActor
@Suite struct NoHubBootTests {
    private static let hubURL = URL(string: "http://hub.test:8000")!

    /// Records every `OnDeviceVerdictWiring.install(hub:)` call the env makes.
    final class InstallRecorder {
        var hubs: [HubDataProvider?] = []
    }

    private func env(secrets: InMemorySecretStore = InMemorySecretStore(), recorder: InstallRecorder? = nil,
                     onDevice: (() -> (any HealthDataProvider)?)? = nil) throws -> AppEnvironment {
        let env = try AppEnvironment(secrets: secrets, inMemory: true)
        if let recorder { env.installOnDeviceVerdict = { recorder.hubs.append($0) } }
        if let onDevice { env.makeOnDeviceProvider = onDevice }
        return env
    }

    @Test func noConfigBuildsAProviderStoreOnTheOnDeviceHealthKitProvider() throws {
        let env = try env()
        try env.boot()
        let store = try #require(env.providerStore)
        #expect(store.provider is HealthKitProvider)
        #expect(env.hubProvider == nil)
        #expect(env.isHubConnected == false)
        // Still "no hub": the first-launch connection sheet and the Today banner key off this.
        #expect(env.needsConnection)
    }

    @Test func noConfigInstallsTheOnDeviceOverlayWithoutAHub() throws {
        let recorder = InstallRecorder()
        let env = try env(recorder: recorder)
        try env.boot()
        #expect(recorder.hubs.count == 1)
        #expect(recorder.hubs.first.map { $0 == nil } == true)   // shadow log hub column nil, nothing to upload to
    }

    @Test func noConfigWithoutHealthKitKeepsTheConnectionPrompt() throws {
        let env = try env(onDevice: { nil })
        try env.boot()
        #expect(env.providerStore == nil)
        #expect(env.needsConnection)
    }

    @Test func savedConfigBootsTheHubProviderAsBefore() throws {
        let secrets = InMemorySecretStore()
        try ConnectionConfigStore(secrets: secrets).save(.init(baseURL: Self.hubURL, token: "t"))
        let recorder = InstallRecorder()
        let env = try env(secrets: secrets, recorder: recorder)
        try env.boot()
        #expect(env.needsConnection == false)
        #expect(env.providerStore?.provider is HubDataProvider)
        #expect(env.providerStore?.provider.capabilities == .hubAll)
        #expect(env.isHubConnected)
        #expect(recorder.hubs.count == 1)
        #expect(recorder.hubs.first.map { $0 != nil } == true)
    }

    @Test func connectingAHubLaterSwitchesTheSameStoreToTheHub() throws {
        let recorder = InstallRecorder()
        let env = try env(recorder: recorder)
        try env.boot()
        let store = try #require(env.providerStore)
        #expect(store.provider is HealthKitProvider)
        env.apply(.init(baseURL: Self.hubURL, token: "t"))
        #expect(env.providerStore === store)
        #expect(store.provider is HubDataProvider)
        #expect(env.isHubConnected)
        #expect(env.needsConnection == false)
        #expect(recorder.hubs.count == 2)
        #expect(recorder.hubs.last.map { $0 != nil } == true)
    }

    // MARK: - RootTabView: the connect prompt is a Today banner, never a full-screen replacement

    @Test func todayShowsTheNoHubBannerOnlyWithoutAHub() throws {
        #expect(RootTabView.showsNoHubBanner(hubConnected: false))
        #expect(!RootTabView.showsNoHubBanner(hubConnected: true))
        #expect(NoHubBanner.title == "On-device mode")
        #expect(NoHubBanner.actionTitle == "Connect hub")
    }

    @Test func coldLaunchOpensTheConnectionSheetOnlyWithoutAnOnDeviceStore() {
        #expect(!RootTabView.coldLaunchAsksForHub(needsConnection: true, onDeviceStore: true))
        #expect(RootTabView.coldLaunchAsksForHub(needsConnection: true, onDeviceStore: false))
        #expect(!RootTabView.coldLaunchAsksForHub(needsConnection: false, onDeviceStore: true))
    }
}
