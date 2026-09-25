import Foundation

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
public nonisolated func metricTintRole(_ kpiId: String) -> JIColorRole {
    switch normalizedMetricKey(kpiId) {
    case "hrv": .hrv   // W-FIX2 BUG-31: `.info` is the accent now
    case "rhr", "restinghr", "resting_hr": .danger
    case "sleep", "sleepscore", "sleep_score": .sleep
    case "steps": .go
    case "load", "acwr", "trainingload", "training_load": .reduced
    // B-57 W1 r5: the macros carry their own design roles (boards: KpiDetailNutrition, WeeklyPlan).
    case "kcal", "calories": .kcal
    case "protein": .protein
    case "carbs", "carbohydrates": .carbs
    case "fat": .fat
    default: .text
    }
}

/// `Load (ACWR)` / `Resting HR` / `sleep_score` all name the same metric — the map keys off a
/// lowercased, separator-free form so a display label and a wire id land on the same role.
nonisolated func normalizedMetricKey(_ kpiId: String) -> String {
    let lowered = kpiId.lowercased()
    // A trailing parenthetical is a human label's suffix ("Load (ACWR)"), not part of the id.
    let head = lowered.split(separator: "(").first.map(String.init) ?? lowered
    return head.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
}
