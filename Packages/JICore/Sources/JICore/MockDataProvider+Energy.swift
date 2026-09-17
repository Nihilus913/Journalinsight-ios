import Foundation

/// W3a-L1 — `MockDataProvider`'s `EnergyProviding` conformance. `MockDataProvider.swift` itself is
/// frozen this wave (three screen lanes would collide on it), so this reuses its public
/// `fixtureURL(named:)` lookup rather than the type's own `private func load` helper (file-scoped
/// access — unreachable from an extension in a different file).
extension MockDataProvider: EnergyProviding {
    public func energy(windowDays: Int) async throws -> EnergyReport {
        try Self.decode(fixture: "nutrition_energy", as: EnergyReport.self)
    }

    public func goals() async throws -> Goals {
        try Self.decode(fixture: "planning_goals", as: Goals.self)
    }

    private static func decode<T: Decodable>(fixture name: String, as type: T.Type) throws -> T {
        guard let url = Self.fixtureURL(named: name)
        else { throw HubError.decoding("missing fixture \(name)") }
        return try JSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }
}
