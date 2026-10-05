import Foundation
import Observation
import SwiftUI
import JICore
import JICompute
import JIPersistence

/// B-57 W3 — the Apple-night series a normal band can be drawn for.
public nonisolated enum RecoveryMetric: Sendable, Hashable { case hrv, rhr, sleepH, deepH, remH }

/// B-57 W3 — the recovery score and the Apple-night normals on the phone (display-only, spec §0.4).
/// Reads `GET /vitals/recovery-inputs` — the 05:10 gate's own loader — for the phone's local day,
/// through `SectionLoader`, so an offline phone keeps the last good inputs. A provider that does not
/// conform (on-device T2), an empty answer or a hub error with no cache gives `reasonWord = "No data"`
/// — never a score of 0 or 50. A night without Apple HRV is `result.status == .missing` (no score).
@Observable @MainActor
public final class RecoveryInsightService {
    /// W-FIX10 R-04: the whole envelope (days + the hub's calibration block) is cached — a new key,
    /// so an older `[RecoveryInputDay]` entry is simply a miss, never a decode failure.
    public static let cacheKey = "recovery.inputs.report"
    public static let windowDays = 42
    public static let staleAfter: TimeInterval = 15 * 60

    public private(set) var days: [RecoveryInputDay] = []
    public private(set) var today: String = ""
    public private(set) var result: RecoveryScoreResult?
    public private(set) var fetchedAt: Date?
    public private(set) var reasonWord: String?
    /// W-FIX10 R-04: the hub's own baseline verdict (HT DH-4); nil from an older hub or a provider
    /// without one. When it says calibrating, the phone never shows a score or band of its own.
    public private(set) var calibration: RecoveryCalibration?
    /// W-B103: the hub's vitals flag (breathing penalty-only + wrist temp display-only).
    public private(set) var vitals = false

    private let provider: (any RecoveryInputsProviding)?
    private let cache: OfflineCache
    private let now: () -> Date
    private let dayKey: (Date) -> String

    public init(provider: (any RecoveryInputsProviding)?, cache: OfflineCache,
                now: @escaping () -> Date = Date.init,
                dayKey: @escaping (Date) -> String = RecoveryInsightService.localDayKey) {
        self.provider = provider; self.cache = cache; self.now = now; self.dayKey = dayKey
    }

    /// The phone's local calendar day — the same "today" the hub gate uses for the hub's timezone.
    public nonisolated static func localDayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public func refresh() async {
        let day = dayKey(now())
        guard let provider else {
            today = day; days = []; calibration = nil; fetchedAt = nil; result = nil; reasonWord = "No data"; return
        }
        let loaded: SectionResult<RecoveryInputsReport>
        do {
            loaded = try await SectionLoader.load(key: Self.cacheKey, cache: cache, now: now) {
                try await provider.recoveryInputsReport(date: day, windowDays: Self.windowDays)
            }
        } catch {
            // Cancellation only (SectionLoader rethrows nothing else): keep what is shown.
            return
        }
        today = day
        days = loaded.value?.days ?? []
        calibration = loaded.value?.calibration
        vitals = loaded.value?.vitals ?? false
        fetchedAt = loaded.fetchedAt ?? fetchedAt
        recompute()
    }

    /// Cheap to call from every card's `.task`: refetches only when never fetched, older than
    /// `staleAfter`, or the day changed.
    public func refreshIfStale() async {
        let stale = fetchedAt.map { now().timeIntervalSince($0) > Self.staleAfter } ?? true
        if stale || today != dayKey(now()) { await refresh() }
    }

    func recompute() {
        result = Self.score(days: days, today: today, calibration: calibration, vitals: vitals)
        reasonWord = result == nil ? "No data" : nil
    }

    /// The recovery score over `/vitals/recovery-inputs` days (nil = no days / no answer). W-DATA
    /// fixer R3: the one computation Decide's ring and the Health screen's Readiness tile share.
    /// W-FIX10 R-04: a hub `calibration` that says calibrating wins — the result is `.calibrating`
    /// with the hub's own night counts (no score), and each component the hub still calibrates
    /// loses its z. The phone never builds a number on nights the hub does not count.
    public nonisolated static func score(days: [RecoveryInputDay], today: String,
                                         calibration: RecoveryCalibration? = nil,
                                         vitals: Bool = false) -> RecoveryScoreResult? {
        let series = days.map { RecoverySeriesDay(date: $0.date, hrvMs: $0.hrvMs, rhrBpm: $0.rhrBpm, sleepH: $0.sleepH,
                                                  deepH: $0.deepH, remH: $0.remH, loadMin: $0.loadMin,
                                                  respBpm: $0.respBpm, wristTempC: $0.wristTempC) }
        guard !series.isEmpty,
              let local = try? RecoveryScore.compute(days: series, today: today, includeVitals: vitals) else { return nil }
        guard let calibration, calibration.calibrating else { return local }
        let comps = local.components.map { c -> RecoveryComponent in
            guard calibration.isCalibrating(c.key.rawValue) else { return c }
            return RecoveryComponent(key: c.key, status: .calibrating, value: c.value, z: nil,
                                     normalN: calibration.component(c.key.rawValue)?.nights ?? c.normalN)
        }
        return RecoveryScoreResult(status: .calibrating, score: nil, raw: nil, components: comps,
                                   nights: calibration.nights, nightsNeeded: calibration.nightsNeeded)
    }

    /// The hub component a metric's normal belongs to.
    nonisolated static func calibrationKey(_ metric: RecoveryMetric) -> String {
        switch metric {
        case .hrv: "hrv"
        case .rhr: "rhr"
        case .sleepH, .deepH, .remH: "sleep"
        }
    }

    /// W-FIX10 R-04: "Calibrating · 4 of 14 nights" while the hub calibrates this metric's normal.
    public func calibrationCaption(for metric: RecoveryMetric) -> String? {
        recoveryCalibrationCaption(calibration, key: Self.calibrationKey(metric))
    }

    private func series(_ metric: RecoveryMetric) -> [String: Double] {
        var out: [String: Double] = [:]
        for d in days {
            let v: Double? = switch metric {
            case .hrv: d.hrvMs
            case .rhr: d.rhrBpm
            case .sleepH: d.sleepH
            case .deepH: d.deepH
            case .remH: d.remH
            }
            if let v, v.isFinite { out[d.date] = v }
        }
        return out
    }

    /// The 28-day personal normal (days `today−34 … today−7`); nil while fewer than 14 values.
    /// W-FIX10 R-04: nil while the hub says this metric's normal is calibrating.
    public func normal(for metric: RecoveryMetric) -> PersonalNormalResult? {
        // W-FIX-P1 RG-09 (B-124): HRV's normal is the hub's one band (the gate's 23–27, 28 nights).
        if metric == .hrv, let hub = hrvHubNormal(calibration) { return hub }
        guard !today.isEmpty, !(calibration?.isCalibrating(Self.calibrationKey(metric)) ?? false) else { return nil }
        return try? PersonalNormal.normal(series(metric), today: today)
    }

    /// The 7-day mean ending today; nil when the window has no value.
    public func sevenDay(for metric: RecoveryMetric) -> Double? {
        if metric == .hrv, hrvHubNormal(calibration) != nil, let v = calibration?.hrv?.rolling7dMs { return v }   // RG-09
        guard !today.isEmpty else { return nil }
        return try? PersonalNormal.windowMean(series(metric), today: today)
    }

    /// The last `count` nights ending today, oldest first; a night with no value is nil (a gap, not 0).
    public func lastNights(_ metric: RecoveryMetric, count: Int) -> [(date: String, value: Double?)] {
        guard !today.isEmpty, count > 0 else { return [] }
        let s = series(metric)
        return (0..<count).reversed().compactMap { k in
            guard let d = try? CalendarMath.addDays(today, -k) else { return nil }
            return (d, s[d])
        }
    }
}

extension RecoveryInsightService {
    /// W-B57-W3 fixer: the Gallery / sweep insight — the mock's 42 deterministic days for a fixed
    /// day, already computed (no fetch: offscreen screens never refresh), so every fixture screen
    /// shows a real score and bands instead of "— No data".
    public static let galleryFixtureDay = "2026-09-24"
    public static let galleryFixture: RecoveryInsightService? = {
        guard let db = try? AppDatabase.inMemory() else { return nil }
        let fixed = Date(timeIntervalSince1970: 1_790_208_000)   // 2026-09-24T00:00Z
        let s = RecoveryInsightService(provider: MockDataProvider(), cache: OfflineCache(db: db),
                                       now: { fixed }, dayKey: { _ in galleryFixtureDay })
        s.today = galleryFixtureDay
        s.days = MockDataProvider.recoveryInputDays(date: galleryFixtureDay, windowDays: windowDays)
        s.calibration = MockDataProvider.recoveryCalibration(nights: 28)
        s.fetchedAt = fixed
        s.recompute()
        return s
    }()
}

extension EnvironmentValues {
    /// B-57 W3: the shared recovery insight (nil = inert: cards show "— No data").
    @Entry public var recoveryInsight: RecoveryInsightService?
}
