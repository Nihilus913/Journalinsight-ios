import Observation

@Observable
@MainActor
public final class ProviderStore {
    public var provider: any HealthDataProvider
    public init(provider: any HealthDataProvider) { self.provider = provider }
}
