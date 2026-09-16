import Foundation

/// A compact "My KPIs" entry: label, optional value, optional unit.
/// A fresh Codable+Sendable projection rather than a reuse of JICore's
/// `DailyKpiRow` — that type shapes a date + a values dictionary, not a
/// single labeled metric, so it doesn't fit the widget's row shape.
public struct SnapshotKPI: Codable, Equatable, Sendable {
    public var label: String
    public var value: Double?
    public var unit: String?

    public init(label: String, value: Double?, unit: String?) {
        self.label = label
        self.value = value
        self.unit = unit
    }
}

/// Widget/complication-facing snapshot of the Home hub's latest morning
/// state. Foundation-only, Codable+Equatable+Sendable so it can round-trip
/// through App-Group `UserDefaults` (see `SnapshotStore`).
///
/// Deliberately excludes the connection token or any other secret — the
/// widget process must never be able to read the hub credential.
public struct HubSnapshot: Codable, Equatable, Sendable {
    /// Projection of JICore's `VerdictParts.word` (e.g. "GO", "REDUCED (session)", "—").
    public var verdictWord: String
    /// Projection of JICore's `VerdictParts.session`.
    public var verdictSession: String
    /// Projection of JICore's `VerdictTone`: "go" / "amber" / "red" / "muted".
    public var verdictTone: String
    /// Projection of JICore's `MorningResponse.verdictDate` (raw wire string, e.g. "2026-09-13").
    public var verdictDate: String?

    /// Latest recovery day's readiness score, 0-100. `nil` when not yet available.
    public var readiness: Double?

    /// Top-N "My KPIs" for the widget face.
    public var kpis: [SnapshotKPI]

    /// When this snapshot was produced by the app/extension.
    public var fetchedAt: Date
    /// Last known hub sync time, if any.
    public var lastSync: Date?

    public init(
        verdictWord: String,
        verdictSession: String,
        verdictTone: String,
        verdictDate: String?,
        readiness: Double?,
        kpis: [SnapshotKPI],
        fetchedAt: Date,
        lastSync: Date?
    ) {
        self.verdictWord = verdictWord
        self.verdictSession = verdictSession
        self.verdictTone = verdictTone
        self.verdictDate = verdictDate
        self.readiness = readiness
        self.kpis = kpis
        self.fetchedAt = fetchedAt
        self.lastSync = lastSync
    }
}
