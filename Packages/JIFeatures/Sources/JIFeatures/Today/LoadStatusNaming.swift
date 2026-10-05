import SwiftUI
import JICore
import JIDesign

// W-B91 S3 (b91p3): the named ACWR status next to the ratio on every Load surface — KPI detail,
// Trends "Load" tile, Recovery "Load" square — the same words Decide's Load row reads (S1). The
// bands are our own (Gabbett 2016, METHODOLOGY §3.2; hub `app/vitals/load_status.py`):
// < 0.80 Maintaining · 0.80–1.30 Productive (inclusive) · > 1.30 Overreaching. Paused only from
// the user's own "I'm on a break" toggle (the hub's load row says `paused`) — never inferred.

/// The hub's lower / upper ACWR band edges (`LOAD_UNDER` / `LOAD_OVER`).
public nonisolated let acwrMaintainingBelow = 0.80
public nonisolated let acwrOverreachingAbove = 1.30

/// The named status for one ACWR. `paused` wins (even without a ratio); no ratio → nil (the
/// surface keeps its own "— No data").
public nonisolated func acwrNamedStatus(_ acwr: Double?, paused: Bool) -> JISignalStatus? {
    if paused { return .paused }
    guard let acwr, acwr.isFinite else { return nil }
    if acwr < acwrMaintainingBelow { return .maintaining }
    return acwr > acwrOverreachingAbove ? .overreaching : .productive
}

/// "1.84 · Overreaching" — the ratio at 2 decimals with its word; "Paused" alone with no ratio.
public nonisolated func acwrStatusText(_ acwr: Double?, paused: Bool) -> String? {
    guard let status = acwrNamedStatus(acwr, paused: paused) else { return nil }
    guard let acwr, acwr.isFinite else { return status.word }
    return "\(jiNumber(acwr, 2)) · \(status.word)"
}

/// true while the hub's `/morning` Load row says the user is on a break (B-91 S1 `load_status`).
public nonisolated func morningLoadPaused(_ morning: MorningResponse?) -> Bool {
    morning?.gateSignals?.contains { $0.key == "load" && $0.loadStatus == "paused" } == true
}

/// KPI detail's Load (ACWR) hero: the named word instead of Up/Down/Steady. Only for the ACWR
/// variant (a minutes Load keeps its own status); a missing or too-old ratio keeps `base`.
public nonisolated func kpiDetailLoadStatus(metric: KpiMetricId, value: Double?, showsLoadMinutes: Bool,
                                            paused: Bool, base: KpiDetailStatus) -> KpiDetailStatus {
    guard metric == .acwr, !showsLoadMinutes else { return base }
    if paused {
        return KpiDetailStatus(word: JISignalStatus.paused.word, symbolName: JISignalStatus.paused.symbolName,
                               detail: "On a break · set by you · ratio not rated", role: JISignalStatus.paused.role)
    }
    guard base.word != "— Old reading", let status = acwrNamedStatus(value, paused: false) else { return base }
    return KpiDetailStatus(word: status.word, symbolName: status.symbolName,
                           detail: "Training load ratio: under 0.80 Maintaining · 0.80–1.30 Productive · over 1.30 Overreaching.",
                           role: status.role)
}

extension EnvironmentValues {
    /// W-B91 S3: the user's break is on (hub `/morning` load row = paused) — every Load surface reads "Paused".
    @Entry public var loadPaused: Bool = false
}
