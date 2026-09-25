import SwiftUI
import JICore
import JIDesign

// B-57 W1 r5 (h3): the More tab's trailing values (board `4 Journal & mind/04 More.png`):
// Nutrition "467 / 1617 kcal", Energy "−598 7-day avg vs TDEE", Goals "80.2 → 75.0 kg",
// Mind "WHO-5 62%". Every figure comes from state the app already loads (the Nutrition / Energy /
// Today / Mind models); a missing input is "—" plus a reason word, never an invented number.

/// One trailing value: `lead` is the figure (or "—"), `rest` the muted tail.
public nonisolated struct MoreRowValue: Sendable, Equatable {
    public enum Style: Sendable, Equatable { case kcal, plain, muted }
    public let lead: String
    public let rest: String
    public let style: Style
    public init(lead: String, rest: String, style: Style) { self.lead = lead; self.rest = rest; self.style = style }
    public var text: String { rest.isEmpty ? lead : "\(lead) \(rest)" }

    static func missing(_ reason: String = JIMissingReason.noData.rawValue) -> MoreRowValue {
        MoreRowValue(lead: "—", rest: reason, style: .muted)
    }
}

private nonisolated func kcalInt(_ v: Double?) -> Int? {
    guard let v, v.isFinite else { return nil }
    return Int(v.rounded())
}

/// Nutrition: today's logged kcal over the day's goal. No logged kcal → "— No data".
public nonisolated func moreNutritionValue(consumedKcal: Double?, goalKcal: Double?) -> MoreRowValue {
    guard let consumed = kcalInt(consumedKcal) else { return .missing() }
    guard let goal = kcalInt(goalKcal), goal > 0 else { return MoreRowValue(lead: "\(consumed)", rest: "kcal", style: .kcal) }
    return MoreRowValue(lead: "\(consumed)", rest: "/ \(goal) kcal", style: .kcal)
}

/// Energy: the 7-day average balance vs TDEE — the same numeral and the same tracking-day gate
/// as the Energy hero (`energyHeroNumeral`, 4 days).
public nonisolated func moreEnergyValue(avgDeficit7d: Double?, trackingDays: Int, minTrackingDays: Int = 4) -> MoreRowValue {
    guard trackingDays >= minTrackingDays, let d = avgDeficit7d, d.isFinite else { return .missing() }
    return MoreRowValue(lead: energyHeroNumeral(d), rest: "7-day avg vs TDEE", style: .kcal)
}

/// Goals: the latest weight → the goals document's target weight.
public nonisolated func moreGoalsValue(currentKg: Double?, targetKg: Double?) -> MoreRowValue {
    guard let target = targetKg, target.isFinite, target > 0 else { return .missing("No goal set") }
    let targetText = String(format: "%.1f", target)
    guard let current = currentKg, current.isFinite, current > 0 else {
        return MoreRowValue(lead: "—", rest: "→ \(targetText) kg", style: .muted)
    }
    return MoreRowValue(lead: String(format: "%.1f", current), rest: "→ \(targetText) kg", style: .plain)
}

/// Mind: the latest WHO-5 percentage. None yet → "— No data".
public nonisolated func moreMindValue(who5Pct: Int?) -> MoreRowValue {
    guard let pct = who5Pct else { return MoreRowValue(lead: "WHO-5 —", rest: JIMissingReason.noData.rawValue, style: .muted) }
    return MoreRowValue(lead: "WHO-5 \(pct)%", rest: "", style: .muted)
}

/// The trailing text of a More row: the figure in its role (calorie tint / bold / muted), the tail
/// muted. Wraps at accessibility sizes instead of truncating.
public struct MoreRowTrailing: View {
    let value: MoreRowValue
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(_ value: MoreRowValue) { self.value = value }

    private var leadColor: Color {
        switch value.style {
        case .kcal: theme.color(nutritionKcalTintRole)
        case .plain: theme.color(.text)
        case .muted: theme.color(.muted)
        }
    }

    public var body: some View {
        let lead = Text(verbatim: value.lead).fontWeight(value.style == .muted ? .regular : .semibold).foregroundStyle(leadColor)
        let rest = Text(verbatim: value.rest.isEmpty ? "" : " \(value.rest)").foregroundStyle(theme.color(.muted))
        Text("\(lead)\(rest)")
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)   // AX sizes stack under the title
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(value.text)
    }
}

/// One More row's label: icon + title leading, the trailing value (`MoreRowTrailing`) after it.
/// The App's More list uses this for every row with a value, so a proof render of it is the row.
public struct MoreRowLabel: View {
    let title: String, systemImage: String, value: MoreRowValue
    public init(_ title: String, systemImage: String, value: MoreRowValue) {
        self.title = title; self.systemImage = systemImage; self.value = value
    }
    public var body: some View {
        LabeledContent { MoreRowTrailing(value) } label: { Label(title, systemImage: systemImage) }
    }
}
