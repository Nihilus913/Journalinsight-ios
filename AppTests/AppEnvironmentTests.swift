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
