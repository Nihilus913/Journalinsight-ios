import JICore

/// W3a-L1 — `HubDataProvider`'s `EnergyProviding` conformance.
///
/// KNOWN GAP (flagged per the coder-prompt's "code against the names the card gives and say so
/// in notes"): `HubDataProvider.swift` is frozen this wave and its `client` property is declared
/// `private let client: HubClient` — `private` in Swift is file-scoped, so an extension in this
/// *different* file cannot reach `self.client` to call `client.get(...)`, even though both files
/// are in the same `JIHub` module. This file is written against the exact shape the card
/// specifies (mirrors `HubDataProvider.recovery(windowDays:)`'s pattern in the frozen file) so the
/// integrator only needs to widen `client`'s access (e.g. to `internal`) in the frozen file to
/// make this compile — no other change needed here.
extension HubDataProvider: EnergyProviding {
    public func energy(windowDays: Int = 7) async throws -> EnergyReport {
        try await client.get("/api/v1/nutrition/energy", query: ["window_days": String(min(windowDays, 365))])
    }

    public func goals() async throws -> Goals {
        try await client.get("/api/v1/planning/goals")
    }
}
