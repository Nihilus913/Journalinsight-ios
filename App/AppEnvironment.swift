import Foundation
import Observation
import JICore
import JIHub
import JIPersistence

@Observable @MainActor
final class AppEnvironment {
    let secrets: any SecretStore
    let cache: OfflineCache
    let prefs: PrefStore
    var providerStore: ProviderStore?
    var needsConnection = false
    private var activeBaseURL: URL?

    init(secrets: any SecretStore = KeychainStore(), inMemory: Bool = false) throws {
        self.secrets = secrets
        cache = OfflineCache(db: inMemory ? try .inMemory() : try .cache())
        prefs = PrefStore(db: inMemory ? try .inMemory() : try .onDisk())
    }

    func boot() throws {
        if let config = try ConnectionConfigStore(secrets: secrets).load() { apply(config) } else { needsConnection = true }
    }

    /// The hub is the only runtime provider. MockDataProvider is previews/tests only (spec §4.2).
    func apply(_ config: ConnectionConfig) {
        if let previous = activeBaseURL, previous != config.baseURL {
            try? cache.clear()
        }
        activeBaseURL = config.baseURL
        let provider = HubDataProvider(client: HubClient(config: config))
        if let store = providerStore { store.provider = provider } else { providerStore = ProviderStore(provider: provider) }
        needsConnection = false
    }
}
