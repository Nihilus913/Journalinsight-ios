import Foundation
import JICore

/// B-47 — the metric → colour-role map every Today/KPI surface tints its numeral with, after
/// Apple Fitness's Summary screen (`docs/design/references/2026-09-22-apple-fitness-summary.png`):
/// the card title stays primary text and the VALUE carries the metric's colour, so a grid of
/// cards reads as six metrics rather than six identical white numbers.
///
/// The roles are `JIColorRole` cases only (B-57 W1 r5 added the four macro roles) — `NativePalette` is frozen this wave, and
/// rule 6's reserved set is respected: `.go`/`.danger` are used for metrics whose own scale is a
/// status (steps against a goal, resting HR), never invented per card.
///
/// Anything unmapped falls back to `.text` — a metric without a colour of its own is primary
/// text, never a random hue (rule 6 again).
///
/// Pure + `nonisolated`: it is a lookup, testable off the main actor and callable from
/// `JIFeatures` (`TodayGrid`) without touching the theme.
///
/// W-KEYS D3r (audit P8): the switch is on `KpiMetricId` — the alias map (`Load (ACWR)`, `sleep_score`,
/// `Resting HR`, `Carbohydrates` …) lives once, in `KpiMetricId(normalizing:)`, not here.
public nonisolated func metricTintRole(_ kpiId: String) -> JIColorRole {
    guard let id = KpiMetricId(normalizing: kpiId) else { return .text }
    return switch id {
    case .hrv: .hrv   // W-FIX2 BUG-31: `.info` is the accent now
    case .rhr: .rhr   // W-GUI F4: coral, not `.danger`
    case .sleep: .sleep
    case .steps: .steps   // W-GUI F4: primary text; `.go` only with a goal (see hasGoal:)
    case .acwr: .load   // W-GUI F4: violet, not `.reduced`
    // B-57 W1 r5: the macros carry their own design roles (boards: KpiDetailNutrition, WeeklyPlan).
    case .kcal: .kcal
    case .protein: .protein
    case .carbs: .carbs
    case .fat: .fat
    case .weight, .bodyBattery, .readiness: .text
    }
}

/// W-GUI F4 (report §4.3): steps against a user goal is a status, so it may wear the reserved
/// `.go`; without a goal it is primary text. Every other metric ignores `hasGoal`.
public nonisolated func metricTintRole(_ kpiId: String, hasGoal: Bool) -> JIColorRole {
    let role = metricTintRole(kpiId)
    return role == .steps && hasGoal ? .go : role
}
