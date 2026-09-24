import Foundation
import Observation
import JICore
import JIPersistence

// MARK: - Banding (pure, ported verbatim from the oracle)

/// E14-D7 — composite-score banding is an engineering-observability CONVENTION over the 0–1
/// `composite` `GET /api/v1/ingestion/quality-score` already computes
/// (`app/ingestion/quality_score.py`), NOT a literature-grounded threshold (HealthTraining
/// CLAUDE.md standing rule: evidence-based methods — labelled as convention here, exactly as the
/// oracle labels it, same as that endpoint's own weights are). Picked from the 2026-09-03 live
/// pull's actual spread (18 rows: 4 <0.4, 4 in [0.4, 0.75), 10 ≥0.75) so all three bands are
/// populated on real data, not just in the fixture.
///
/// Verbatim from `mobile/app/data-quality.tsx:19–20`.
public nonisolated enum DataQualityBands {
    public static let greenMin: Double = 0.75
    public static let amberMin: Double = 0.4
}

/// The screen's three-way tone (oracle `Tone` in `data-quality.tsx`). `go`/`amber`/`red` are the
/// oracle's own names; the colour mapping lives in the view.
public nonisolated enum DataQualityTone: String, Sendable, Equatable, CaseIterable {
    case go, amber, red

    /// Oracle `TONE_LABEL`.
    public var label: String {
        switch self {
        case .go: "Green"
        case .amber: "Amber"
        case .red: "Red"
        }
    }

    /// Worst-first ordering rank (oracle `rank` in `data-quality.tsx`).
    public var rank: Int {
        switch self {
        case .red: 0
        case .amber: 1
        case .go: 2
        }
    }
}

/// Oracle `compositeTone`.
public nonisolated func dataQualityCompositeTone(_ composite: Double) -> DataQualityTone {
    if composite >= DataQualityBands.greenMin { return .go }
    if composite >= DataQualityBands.amberMin { return .amber }
    return .red
}

/// Oracle `freshnessTone` — the hub's traffic light mapped onto the screen's tone.
public nonisolated func dataQualityFreshnessTone(_ state: FreshnessState) -> DataQualityTone {
    switch state {
    case .green: .go
    case .amber: .amber
    case .red: .red
    }
}

/// Oracle `TRUST_LABEL`, with its `?? entry.trust_tier` fallback for a tier this build doesn't
/// know (`ref.source_trust` is seeded data the hub may extend without an app release).
public nonisolated func dataQualityTrustLabel(_ tier: String) -> String {
    switch tier {
    case "trusted": "Trusted"
    case "flagged": "Flagged"
    case "low": "Low trust"
    default: tier
    }
}

/// Oracle `pct` — a nil sub-score reads as an em dash, NEVER as 0% (rule 5).
public nonisolated func dataQualityPercent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return "\(Int((value * 100).rounded()))%"
}

/// Oracle: the trust tone in `SourceTrustRow` (`trusted` → go, `flagged` → amber, else red).
public nonisolated func dataQualityTrustTone(_ tier: String) -> DataQualityTone {
    switch tier {
    case "trusted": .go
    case "flagged": .amber
    default: .red
    }
}

/// Worst-first sort, the same ordering convention as the hub's own `/freshness` response — the
/// rows most worth a look land at the top of the scroll (oracle `sortedScores`). Stable within a
/// band (Swift's `sorted` is documented stable), so equal tones keep the hub's own order.
public nonisolated func dataQualitySortedScores(_ rows: [QualityScoreEntry]) -> [QualityScoreEntry] {
    rows.sorted { dataQualityCompositeTone($0.composite).rank < dataQualityCompositeTone($1.composite).rank }
}

/// `(source, metric)` → freshness detail, the join the per-row freshness line reads
/// (oracle `freshByKey`).
public nonisolated func dataQualityFreshnessByKey(_ rows: [FreshnessEntry]) -> [String: FreshnessEntry] {
    Dictionary(rows.map { (DataQualityReport.joinKey(source: $0.source, metric: $0.metric), $0) }) { first, _ in first }
}

// MARK: - Provider access

/// W5b-L1 seam between the Data Quality UI (a Settings row and the Today freshness badge, neither
/// of which owns a provider) and the app, which is the only layer that builds a concrete one.
///
/// A single shared instance rather than a `SettingsViewModel` field, for exactly the reason
/// `ProviderSwitch` (W7-L3) is one: that view model is frozen after W5a-L0 — a lane may add a
/// section, never a field. `App` installs the live `HubDataProvider` once at boot; until it does,
/// `provider` is nil and both entry points render an honest "not available" state rather than a
/// dead row (rule 5).
@Observable @MainActor
public final class DataQualityAccess {
    public static let shared = DataQualityAccess()
    public private(set) var provider: (any DataQualityProviding)?
    public init() {}
    public func install(_ provider: (any DataQualityProviding)?) { self.provider = provider }
    /// Builds the screen's view model against the installed provider, or nil when none is wired.
    public func makeViewModel(cache: OfflineCache? = nil) -> DataQualityViewModel? {
        guard let provider else { return nil }
        return DataQualityViewModel(provider: provider, cache: cache)
    }
}

// MARK: - View model

/// E14-D7 / W5b-L1 — the Data Quality detail screen's model. One `DataQualityProviding.dataQuality()`
/// call (which fans out to the three hub GETs and merges behind the seam), therefore exactly one
/// phase and one error, mirroring the oracle's single `useDataQuality` hook.
///
/// Error precedence and the cancellation contract follow `KpiListViewModel` (CODE-1): a cancelled
/// load returns to `.idle` rather than reporting a false error, and a live failure with a cache hit
/// still renders the carried-over report behind a staleness banner.
@Observable @MainActor
public final class DataQualityViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, empty, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var report: DataQualityReport?
    public private(set) var fetchedAt: Date?
    public private(set) var hubReachable = true
    public private(set) var hasLiveResult = false
    public private(set) var lastError: HubError?

    /// W8-L4: DESIGN-7 `ScreenState` over the same signals `phase` already tracks — resolved,
    /// never a second state machine. No verdict date on this screen, so `.staleVerdictDate` can't
    /// arise; `.neverSynced` = a first-ever load that came back empty with no cache to show.
    public var screenState: ScreenState {
        ScreenState.resolve(
            phase: mappedPhase, neverSynced: report == nil && fetchedAt == nil,
            verdictDate: nil, todayDateString: "", lastError: lastError
        )
    }

    private var mappedPhase: TodayViewModel.Phase {
        switch phase {
        case .idle: .idle
        case .loading: .loading
        case .loaded: .loaded
        case .empty: .empty
        case .error(let message): .error(message)
        }
    }

    private let provider: any DataQualityProviding
    /// Optional: the Settings row and the Today badge can both build this model without one, and
    /// the oracle's `withOfflineCache("dataQuality")` fallback is simply skipped when absent.
    private let cache: OfflineCache?
    static let cacheKey = "dataQuality"

    public init(provider: any DataQualityProviding, cache: OfflineCache? = nil) {
        self.provider = provider
        self.cache = cache
    }

    /// Worst-first rows (oracle `sortedScores`).
    public var sortedScores: [QualityScoreEntry] { dataQualitySortedScores(report?.qualityScore ?? []) }
    public var sourceTrust: [SourceTrustEntry] { report?.sourceTrust ?? [] }
    public var provenanceGap: String? { report?.provenanceGap }
    /// B-57 W1 board: per-source freshness for the summary card and the Sources rows.
    public var sourceSummary: DataQualitySourceSummary { dataQualitySourceSummary(report?.freshness ?? []) }
    /// B-57 W1 r4: the three compact per-source rows; the per-metric detail sits one level down.
    public var families: [DataQualityFamilyRow] { dataQualityFamilies(report) }

    /// The freshness detail paired with a quality row, or nil when the hub's two reports don't
    /// line up for it — the screen then prints "—" rather than inventing a state.
    public func freshness(for entry: QualityScoreEntry) -> FreshnessEntry? {
        freshnessByKey[DataQualityReport.joinKey(source: entry.source, metric: entry.metric)]
    }

    private var freshnessByKey: [String: FreshnessEntry] { dataQualityFreshnessByKey(report?.freshness ?? []) }

    public func load() async {
        if report == nil { phase = .loading }
        restoreFromCache()
        await fetch()
    }

    public func refresh() async { await fetch() }

    private func restoreFromCache() {
        guard report == nil, let cache, let hit = try? cache.get(Self.cacheKey, as: DataQualityReport.self) else { return }
        report = hit.value
        fetchedAt = hit.fetchedAt
        phase = .loaded
    }

    private func fetch() async {
        do {
            let value = try await provider.dataQuality()
            try? cache?.put(Self.cacheKey, value)
            report = value
            fetchedAt = Date()
            hubReachable = true
            hasLiveResult = true
            lastError = nil
            phase = isEmpty(value) ? .empty : .loaded
        } catch {
            if Task.isCancelled {
                if phase == .loading { phase = .idle }
                return
            }
            let hubError = (error as? HubError) ?? .decoding("\(error)")
            lastError = hubError
            if case .network = hubError { hubReachable = false } else { hubReachable = true }
            phase = report == nil ? .error(Self.describe(hubError)) : .loaded
        }
    }

    private func isEmpty(_ report: DataQualityReport) -> Bool {
        report.qualityScore.isEmpty && report.freshness.isEmpty && report.sourceTrust.isEmpty
    }

    /// Same copy as every other screen's hub failure (CODE-1), so one outage reads identically
    /// wherever the user happens to be.
    static func describe(_ error: HubError) -> String {
        switch error {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .yazioAuthExpired(let detail): "Hub error: \(detail)"
        default: "Couldn't load data quality."
        }
    }
}

/// B-57 W1: YAZIO is a source read through Apple Health (v10 change "YAZIO via Apple Health").
public nonisolated func dataQualitySourceDisplay(_ source: String) -> String {
    source.lowercased() == "yazio" ? JIExplainers.nutritionSourceLabel : source
}

// MARK: - B-57 W1 board summary (fixer f3)

/// One source's worst freshness state across its metrics (the board's "Sources" rows).
nonisolated public struct DataQualitySourceState: Sendable, Equatable, Identifiable {
    public let source: String
    public let state: FreshnessState
    /// Days stale of the worst metric; nil when the hub did not say.
    public let daysStale: Int?
    public var id: String { source }
}

/// The board's "Sources fresh today — n of N" card: one entry per source the hub reports.
nonisolated public struct DataQualitySourceSummary: Sendable, Equatable {
    public let sources: [DataQualitySourceState]
    public var fresh: Int { sources.filter { $0.state == .green }.count }
    public var stale: Int { sources.count - fresh }
}

public nonisolated func dataQualitySourceSummary(_ rows: [FreshnessEntry]) -> DataQualitySourceSummary {
    func rank(_ s: FreshnessState) -> Int { s == .red ? 2 : s == .amber ? 1 : 0 }
    var worst: [String: DataQualitySourceState] = [:]
    for row in rows {
        if let current = worst[row.source] {
            if rank(row.state) > rank(current.state) {
                worst[row.source] = DataQualitySourceState(source: row.source, state: row.state, daysStale: row.daysStale)
            } else if rank(row.state) == rank(current.state), let d = row.daysStale, d > (current.daysStale ?? -1) {
                worst[row.source] = DataQualitySourceState(source: row.source, state: row.state, daysStale: d)
            }
        } else {
            worst[row.source] = DataQualitySourceState(source: row.source, state: row.state, daysStale: row.daysStale)
        }
    }
    return DataQualitySourceSummary(sources: worst.values.sorted { $0.source < $1.source })
}

// MARK: - B-57 W1 r4 per-source quality rows (fixer g3, board 5/07)

/// The board's three "Per-source quality" rows. The hub reports per (source, metric) with a
/// `dso_key`; GarminDB (1) and GarminAPI (2) are one Garmin row. A source outside the three
/// (Manual, a future one) gets an "Other" row so its detail never disappears.
public nonisolated enum DataQualityFamily: String, Sendable, Equatable, CaseIterable, Identifiable {
    case appleWatch, garmin, yazio, other
    public var id: String { rawValue }

    public init(dsoKey: Int, source: String) {
        switch dsoKey {
        case 1, 2: self = .garmin
        case 3: self = .yazio
        case 4: self = .appleWatch
        default:
            let s = source.lowercased()
            if s.hasPrefix("garmin") { self = .garmin }
            else if s == "yazio" { self = .yazio }
            else if s == "applehealth" { self = .appleWatch }
            else { self = .other }
        }
    }

    public var title: String {
        switch self {
        case .appleWatch: "Apple Watch"
        case .garmin: "Garmin"
        case .yazio: "YAZIO"
        case .other: "Other sources"
        }
    }
}

public nonisolated struct DataQualityFamilyRow: Sendable, Equatable, Identifiable {
    public let family: DataQualityFamily
    /// Worst first, as the old flat list was.
    public let scores: [QualityScoreEntry]
    public let trust: [SourceTrustEntry]
    public var id: String { family.id }
    /// Mean composite of this source's metric rows, 0–100; nil when the hub scored none.
    public var percent: Int? {
        guard !scores.isEmpty else { return nil }
        return Int((scores.map(\.composite).reduce(0, +) / Double(scores.count) * 100).rounded())
    }
    public var trailing: String { percent.map { "\($0)%" } ?? "— No data" }
    public var tone: DataQualityTone? {
        guard !scores.isEmpty else { return nil }
        return dataQualityCompositeTone(Double(percent ?? 0) / 100)
    }
}

/// Apple Watch · Garmin · YAZIO always (the board's rows; an empty one says "— No data"), plus
/// "Other sources" only when the hub reported one.
public nonisolated func dataQualityFamilies(_ report: DataQualityReport?) -> [DataQualityFamilyRow] {
    let scores = dataQualitySortedScores(report?.qualityScore ?? [])
    let trust = report?.sourceTrust ?? []
    return DataQualityFamily.allCases.compactMap { family in
        let s = scores.filter { DataQualityFamily(dsoKey: $0.dsoKey, source: $0.source) == family }
        let t = trust.filter { DataQualityFamily(dsoKey: $0.dsoKey, source: $0.sourceLabel) == family }
        if family == .other, s.isEmpty, t.isEmpty { return nil }
        return DataQualityFamilyRow(family: family, scores: s, trust: t)
    }
}
