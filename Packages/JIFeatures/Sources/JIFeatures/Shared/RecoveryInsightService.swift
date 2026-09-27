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
    public static let cacheKey = "recovery.inputs"
    public static let windowDays = 42
    public static let staleAfter: TimeInterval = 15 * 60

    public private(set) var days: [RecoveryInputDay] = []
    public private(set) var today: String = ""
    public private(set) var result: RecoveryScoreResult?
    public private(set) var fetchedAt: Date?
    public private(set) var reasonWord: String?

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
            today = day; days = []; fetchedAt = nil; result = nil; reasonWord = "No data"; return
        }
        let loaded: SectionResult<[RecoveryInputDay]>
        do {
            loaded = try await SectionLoader.load(key: Self.cacheKey, cache: cache, now: now) {
                try await provider.recoveryInputs(date: day, windowDays: Self.windowDays)
            }
        } catch {
            // Cancellation only (SectionLoader rethrows nothing else): keep what is shown.
            return
        }
        today = day
        days = loaded.value ?? []
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
        let series = days.map { RecoverySeriesDay(date: $0.date, hrvMs: $0.hrvMs, rhrBpm: $0.rhrBpm, sleepH: $0.sleepH,
                                                  deepH: $0.deepH, remH: $0.remH, loadMin: $0.loadMin) }
        guard !series.isEmpty else { result = nil; reasonWord = "No data"; return }
        result = try? RecoveryScore.compute(days: series, today: today)
        reasonWord = result == nil ? "No data" : nil
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
    public func normal(for metric: RecoveryMetric) -> PersonalNormalResult? {
        guard !today.isEmpty else { return nil }
        return try? PersonalNormal.normal(series(metric), today: today)
    }

    /// The 7-day mean ending today; nil when the window has no value.
    public func sevenDay(for metric: RecoveryMetric) -> Double? {
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

extension EnvironmentValues {
    /// B-57 W3: the shared recovery insight (nil = inert: cards show "— No data").
    @Entry public var recoveryInsight: RecoveryInsightService?
}
