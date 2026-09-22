import Foundation
import Testing
import JIHub
@testable import JournalInsight

@Test @MainActor func bootWithoutConfigAsksForConnection() throws {
    let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true)
    try env.boot()
    #expect(env.needsConnection)
    #expect(env.providerStore == nil)
}

@Test @MainActor func bootWithConfigBuildsHubProvider() throws {
    let secrets = InMemorySecretStore()
    try ConnectionConfigStore(secrets: secrets).save(.init(baseURL: URL(string: "http://hub.test:8000")!, token: "t"))
    let env = try AppEnvironment(secrets: secrets, inMemory: true)
    try env.boot()
    #expect(env.needsConnection == false)
    #expect(env.providerStore?.provider.capabilities == .hubAll)
}

// MARK: - B-46 (L1) launch-argument hub injection

// The simulator repro of the B-46 device defects needs the app pointed at the live hub without a
// hand-driven Connection sheet; `-hub-url`/`-hub-token` do that in DEBUG builds only.
@Test func launchArgumentConfigReadsAUrlAndToken() throws {
    let config = try #require(AppEnvironment.launchArgumentConfig(["app", "-hub-url", "http://localhost:8000", "-hub-token", "tok"]))
    #expect(config.baseURL == URL(string: "http://localhost:8000"))
    #expect(config.token == "tok")
}

@Test func launchArgumentConfigIsNilWithoutBothFlags() {
    #expect(AppEnvironment.launchArgumentConfig(["app"]) == nil)
    #expect(AppEnvironment.launchArgumentConfig(["app", "-hub-url", "http://localhost:8000"]) == nil)
    #expect(AppEnvironment.launchArgumentConfig(["app", "-hub-token", "tok"]) == nil)
    #expect(AppEnvironment.launchArgumentConfig(["app", "-hub-url"]) == nil)
}
