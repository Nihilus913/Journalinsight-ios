import Foundation
import JICore
import JICompute
import JIDesign

// B-104 p2 — the HRV KPI detail's merged series: the Watch nights the screen already plots plus
// the Garmin-era nights (2025-05..2026-09) from `/vitals/recovery-inputs` (`hrv_src` "garmin",
// already × 0.95 hub-side = an estimate). Garmin nights are drawn (dashed, other tint, "est.") but
// never enter the band, the 7-day average or the 28-day count — those stay Watch-only (card
// default 1). A hole (no reading for > `kpiHrvGapDays` days, e.g. 2026-09-13..18) is a gap, never
// a bridged line and never a zero (rule 5).

/// One night on the merged HRV chart.
public nonisolated struct KpiSourcedPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let value: Double
    public let source: HrvNightSource
    public var id: Date { date }
    public var isEstimate: Bool { source == .garmin }
    public init(date: Date, value: Double, source: HrvNightSource) { self.date = date; self.value = value; self.source = source }
}

/// One unbroken run of same-source nights: drawn as one line (one point = a dot).
public nonisolated struct KpiTrendSegment: Sendable, Equatable, Identifiable {
    public let id: Int
    public let source: HrvNightSource
    public let points: [TrendPoint]
    public var isEstimate: Bool { source == .garmin }
}

/// Missing nights the line may bridge; a longer run of missing nights is drawn as a gap.
public nonisolated let kpiHrvGapDays = 2

/// The legend's words for the Garmin style (Toby 2026-10-04: scaled × 0.95, labelled "est.").
public nonisolated let kpiHrvGarminLegend = "dashed grey = Garmin × 0.95 (est.)"
/// The caption under the legend: what the band / average are built from.
/// W-FIX-P1 RG-09 (B-124): the band is the hub's one band — the gate's 28 nights (Watch first,
/// Garmin × 0.95 on nights without a Watch value); the Watch-only 28-night rule is gone.
public nonisolated let kpiHrvMixCaption = "Band, 7-day average and night count are the morning call's: your last 28 nights, Watch first, Garmin × 0.95 where the Watch has none."

/// The merged series over `range`: every Watch night of `history` (already Watch-only via
/// `kpiSourceFilteredHistory`) plus every Garmin night of `sourceDays` the Watch has no value for.
/// The range ends at the newest night of either source. No Garmin rows (older hub, mock) = the
/// Watch series alone, exactly as before.
public nonisolated func kpiHrvMergedPoints(history: [(date: String, value: Double?)], sourceDays: [RecoveryInputDay],
                                           range: KpiDetailRange) -> [KpiSourcedPoint] {
    var byDay: [String: (Double, HrvNightSource)] = [:]
    for d in sourceDays where d.isGarminHrv { if let v = d.hrvMs { byDay[d.date] = (v, .garmin) } }
    for h in history { if let v = h.value { byDay[h.date] = (v, .apple) } }   // the Watch wins a shared night
    let dated = byDay.compactMap { key, v -> KpiSourcedPoint? in
        guard let date = trainingStripDate(key) else { return nil }
        return KpiSourcedPoint(date: date, value: v.0, source: v.1)
    }
    guard let newest = dated.map(\.date).max(),
          let cutoff = trainingStripCalendar.date(byAdding: .day, value: -(range.days - 1), to: newest) else { return [] }
    return dated.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
}

/// Splits the merged points into runs: a new run starts on a source change or after a hole longer
/// than `kpiHrvGapDays` missing nights.
public nonisolated func kpiHrvSegments(_ points: [KpiSourcedPoint]) -> [KpiTrendSegment] {
    var out: [KpiTrendSegment] = []
    var run: [KpiSourcedPoint] = []
    func flush() {
        guard let first = run.first else { return }
        out.append(KpiTrendSegment(id: out.count, source: first.source, points: run.map { TrendPoint(date: $0.date, value: $0.value) }))
        run = []
    }
    for p in points {
        if let last = run.last {
            let days = trainingStripCalendar.dateComponents([.day], from: last.date, to: p.date).day ?? 0
            if p.source != last.source || days > kpiHrvGapDays + 1 { flush() }
        }
        run.append(p)
    }
    flush()
    return out
}

/// "16 Watch + 74 Garmin" — the nights each source puts on the chart. Nil when no Garmin night is
/// on it (the row is then not shown; the Watch-only screen stays as it was).
public nonisolated func kpiHrvSourceCountText(_ points: [KpiSourcedPoint]) -> String? {
    let garmin = points.filter(\.isEstimate).count
    guard garmin > 0 else { return nil }
    return "\(points.count - garmin) Watch + \(garmin) Garmin"
}

/// The table row for the merged chart (nil = no Garmin night on it).
public nonisolated func kpiHrvSourceRow(_ points: [KpiSourcedPoint], range: KpiDetailRange) -> KpiDetailTableRow? {
    kpiHrvSourceCountText(points).map {
        KpiDetailTableRow(id: "sources", title: "Nights counted", subtitle: "on the \(range.label) chart · Garmin = est.", value: $0)
    }
}

/// The table with the merged row: the 28-day Watch-only count is renamed "Watch nights (28 d)" so
/// the two counts never share a title, and "Nights counted" = the chart's own per-source count.
/// No Garmin night on the chart = the rows unchanged.
public nonisolated func kpiHrvTableRows(_ rows: [KpiDetailTableRow], merged: [KpiSourcedPoint]?, range: KpiDetailRange) -> [KpiDetailTableRow] {
    guard let merged, let source = kpiHrvSourceRow(merged, range: range) else { return rows }
    return rows.map { r in
        r.id == "counted" ? KpiDetailTableRow(id: r.id, title: "Watch nights (28 d)", subtitle: "the normal's nights · missing ones stay missing", value: r.value) : r
    } + [source]
}
