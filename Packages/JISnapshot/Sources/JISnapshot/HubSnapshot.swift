import Foundation
import JICore

/// A compact "My KPIs" entry: label, optional value, optional unit.
/// A fresh Codable+Sendable projection rather than a reuse of JICore's
/// `DailyKpiRow` — that type shapes a date + a values dictionary, not a
/// single labeled metric, so it doesn't fit the widget's row shape.
public struct SnapshotKPI: Codable, Equatable, Sendable {
    /// W-B34 (B-36): stable KPI identity so a configured widget can find "the KPI the user picked"
    /// without matching on label text. Optional so snapshots stored before W-B34 still decode;
    /// Today's chip projection (`kpis`) may leave it nil.
    public var id: KpiMetricId?
    public var label: String
    public var value: Double?
    public var unit: String?

    public init(id: KpiMetricId? = nil, label: String, value: Double?, unit: String?) {
        self.id = id
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

    /// W-B34 (B-36): one entry per `KpiMetricId.allCases` (latest non-nil value, or nil) for the
    /// configurable KPI widget. Optional so snapshots stored before W-B34 still decode (nil).
    public var allKpis: [SnapshotKPI]?

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
        allKpis: [SnapshotKPI]? = nil,
        fetchedAt: Date,
        lastSync: Date?
    ) {
        self.verdictWord = verdictWord
        self.verdictSession = verdictSession
        self.verdictTone = verdictTone
        self.verdictDate = verdictDate
        self.readiness = readiness
        self.kpis = kpis
        self.allKpis = allKpis
        self.fetchedAt = fetchedAt
        self.lastSync = lastSync
    }

    /// W-B34 (B-36): the snapshot entry for one KPI — `allKpis` first, then Today's `kpis`, matched
    /// by `id` (never by label). nil when neither carries it (e.g. a pre-W-B34 snapshot).
    public func kpi(_ id: KpiMetricId) -> SnapshotKPI? {
        allKpis?.first { $0.id == id } ?? kpis.first { $0.id == id }
    }
}
