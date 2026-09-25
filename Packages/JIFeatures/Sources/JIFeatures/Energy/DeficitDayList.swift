import SwiftUI
import JICore
import JICompute
import JIDesign

// B-57 W1 r4 (board `2 Monitor/06 Energy.png`): the "This week" bars and the Daily log, over the
// hub's energy days and the user's calorie goal. Pure helpers first, then the two views.

/// B-57 W2 (B-73): the plan band is the user's own kcal target ± 100 (`EnergyBand.halfWidthKcal`),
/// the same band the hero and GoalsSetup show (was ± 5 % of the hub goal, W-FIX3 BUG-39).
public nonisolated let energyPlanBandHalfWidth = Double(EnergyBand.halfWidthKcal)

/// One day of the log in the explainer's words ("Deficit or surplus" in `JIExplainers`):
/// inside the plan band = On plan; below it = Deep deficit; above it = Light deficit, and a
/// balance above 0 = Surplus. Above the band with no burn figure the sign is unknown, so it
/// says only that ("Above plan band") rather than guessing deficit or surplus.
public nonisolated enum EnergyDayStatus: Equatable, Sendable {
    case onPlan, deepDeficit, lightDeficit, surplus, abovePlan, noGoal
    case missing(JIMissingReason)

    public var word: String {
        switch self {
        case .onPlan: "On plan"
        case .deepDeficit: "Deep deficit"
        case .lightDeficit: "Light deficit"
        case .surplus: "Surplus"
        case .abovePlan: "Above plan band"
        case .noGoal: MacroGoals.setGoalCopy
        case .missing(let reason): "— \(reason.rawValue)"
        }
    }

    public var role: JIColorRole {
        switch self {
        case .onPlan: .go
        case .deepDeficit: .reduced
        case .lightDeficit: .info
        case .surplus, .abovePlan, .noGoal, .missing: .muted
        }
    }

    public var symbolName: String {
        switch self {
        case .onPlan: "checkmark"
        case .deepDeficit: "arrow.down"
        case .lightDeficit: "arrow.down.right"
        case .surplus, .abovePlan: "arrow.up"
        case .noGoal, .missing: "minus"
        }
    }
}

/// The plan band around the user's kcal target, or nil without one.
public nonisolated func energyPlanBand(goal: Double?) -> ClosedRange<Double>? {
    guard let goal, goal.isFinite, goal > 0 else { return nil }
    let t = goal.rounded()
    return (t - energyPlanBandHalfWidth)...(t + energyPlanBandHalfWidth)
}

/// "Plan band 1700–1900 kcal", or "Set your goal".
public nonisolated func energyPlanBandText(_ goal: Double?) -> String {
    guard let band = energyPlanBand(goal: goal) else { return EnergyDayStatus.noGoal.word }
    return "Plan band \(jiNumber(band.lowerBound, 0))–\(jiNumber(band.upperBound, 0)) kcal"
}

/// `deficit` is the hub's `deficit_corrected` (burn − intake; negative = surplus).
public nonisolated func energyDayStatus(intake: Double?, goal: Double?, deficit: Double? = nil) -> EnergyDayStatus {
    guard let intake, intake.isFinite else { return .missing(.noData) }
    guard let band = energyPlanBand(goal: goal) else { return .noGoal }
    if band.contains(intake) { return .onPlan }
    if intake < band.lowerBound { return .deepDeficit }
    guard let deficit, deficit.isFinite else { return .abovePlan }
    return deficit < 0 ? .surplus : .lightDeficit
}

/// One bar of "This week" (Monday first). `kcal` is nil for a day with no intake and for days
/// still to come — drawn as "—", never a zero bar.
public nonisolated struct EnergyWeekBar: Identifiable, Equatable, Sendable {
    public let id: String      // ISO date
    public let label: String   // "Mon"
    public let kcal: Double?
    public let isToday: Bool
    public let isFuture: Bool
}

private nonisolated let energyWeekdayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
private nonisolated let energyWeekdayLong = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

/// Monday-first index (0…6) of an ISO date.
nonisolated func energyWeekdayIndex(_ iso: String) -> Int? {
    guard let d = trainingStripDate(iso) else { return nil }
    return (trainingStripCalendar.component(.weekday, from: d) + 5) % 7
}

/// Today's ISO date on the device's own calendar (the energy days are local calendar days).
public nonisolated func energyTodayISO(_ now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: now)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// The current week, Monday to Sunday, with each day's intake from `days`.
public nonisolated func energyWeekBars(days: [EnergyDay], today: String) -> [EnergyWeekBar] {
    guard let todayDate = trainingStripDate(today), let idx = energyWeekdayIndex(today),
          let monday = trainingStripCalendar.date(byAdding: .day, value: -idx, to: todayDate) else { return [] }
    let byDate = Dictionary(days.map { ($0.date, $0.kcalConsumed) }, uniquingKeysWith: { a, _ in a })
    return (0..<7).compactMap { i in
        guard let d = trainingStripCalendar.date(byAdding: .day, value: i, to: monday) else { return nil }
        let iso = trainingStripISO(d)
        let future = iso > today
        return EnergyWeekBar(id: iso, label: energyWeekdayShort[i], kcal: future ? nil : (byDate[iso] ?? nil),
                             isToday: iso == today, isFuture: future)
    }
}

/// "Wednesday is still filling in." — only when today already has intake in the week.
public nonisolated func energyFillingInCaption(days: [EnergyDay], today: String) -> String? {
    guard let day = days.first(where: { $0.date == today }), day.kcalConsumed != nil,
          let idx = energyWeekdayIndex(today) else { return nil }
    return "\(energyWeekdayLong[idx]) is still filling in."
}

/// The log's days: complete days only (today counts once it ends), newest first.
public nonisolated func energyLogDays(days: [EnergyDay], today: String) -> [EnergyDay] {
    days.filter { $0.date < today }.sorted { $0.date > $1.date }
}

/// "Tue 22".
public nonisolated func energyLogDateLabel(_ iso: String) -> String {
    guard let idx = energyWeekdayIndex(iso), let day = iso.split(separator: "-").last.flatMap({ Int($0) }) else { return iso }
    return "\(energyWeekdayShort[idx]) \(day)"
}

/// A weekday column label: "Wed", or "We" at accessibility sizes.
public nonisolated func energyWeekdayLabel(_ label: String, accessibilitySize: Bool) -> String {
    accessibilitySize ? String(label.prefix(2)) : label
}

/// Board "This week": one intake bar per day in the calorie tint, the user's goal as a dashed
/// line, today's bar hatched while it fills in, "—" for a day with nothing yet.
struct EnergyWeekChart: View {
    let bars: [EnergyWeekBar]
    let goal: Double?
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var barMaxHeight: CGFloat = 110

    private var scaleTop: Double {
        max(bars.compactMap(\.kcal).max() ?? 0, goal ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(bars) { bar in column(bar) }
            }
            .overlay(alignment: .bottom) { goalLine }
        }
        .accessibilityIdentifier("energy.thisWeek")
    }

    @ViewBuilder
    private var goalLine: some View {
        if let goal, goal > 0 {
            GeometryReader { g in
                // Bars sit above a label row; the line is measured from the bars' baseline.
                let y = g.size.height - labelRowHeight - 4 - barMaxHeight * CGFloat(goal / scaleTop)
                Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y)) }
                    .stroke(theme.color(.go).opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ScaledMetric(relativeTo: .footnote) private var labelRowHeight: CGFloat = 22
    /// Room above the tallest bar for its number (and the column's spacing).
    @ScaledMetric(relativeTo: .caption) private var valueRowHeight: CGFloat = 30

    private func column(_ bar: EnergyWeekBar) -> some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            if let kcal = bar.kcal {
                Text(jiNumber(kcal, 0)).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.text))
                    .lineLimit(1).minimumScaleFactor(0.5)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.color(nutritionKcalTintRole).opacity(bar.isToday ? 0.45 : 1))
                    .overlay {
                        if bar.isToday {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(theme.color(nutritionKcalTintRole), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        }
                    }
                    .frame(height: max(6, barMaxHeight * CGFloat(kcal / scaleTop)))
            } else {
                Text("—").jiFont(.caption).foregroundStyle(theme.color(.muted))
                Capsule().fill(theme.color(.nested)).frame(height: 3)
            }
            // AX3: three letters cannot fit a seventh of the card, so the label shortens to two
            // (the column's VoiceOver label keeps the full day) instead of truncating to "W…".
            Text(energyWeekdayLabel(bar.label, accessibilitySize: typeSize.isAccessibilitySize))
                .jiFont(.footnote, weight: bar.isToday ? .bold : .regular)
                .foregroundStyle(theme.color(bar.isToday ? .text : .muted))
                .lineLimit(1).minimumScaleFactor(0.5).allowsTightening(true)
                .frame(height: labelRowHeight)
        }
        .frame(maxWidth: .infinity).frame(height: barMaxHeight + labelRowHeight + valueRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bar.label)
        .accessibilityValue(bar.kcal.map { "\(jiNumber($0, 0)) kcal\(bar.isToday ? ", still filling in" : "")" }
                            ?? (bar.isFuture ? "still to come" : JIMissingReason.noData.rawValue))
        .accessibilityIdentifier("energy.week.\(bar.id)")
    }
}

/// Board "Daily log": one row per complete day, newest first — "Tue 22 · 1619 kcal · ✓ On plan".
/// Display-only (the RN tap-through to Nutrition on that date has no Swift route yet).
public struct DeficitDayList: View {
    private let days: [EnergyDay]
    private let goal: Double?
    private let today: String
    @Environment(\.jiTheme) private var theme

    public init(days: [EnergyDay], goal: Double? = nil, today: String = energyTodayISO()) {
        self.days = days; self.goal = goal; self.today = today
    }

    public var body: some View {
        let log = energyLogDays(days: days, today: today)
        VStack(alignment: .leading, spacing: 0) {
            // W-FIX3 BUG-39: the band the words are judged against, not a single goal figure.
            Text(energyPlanBandText(goal)).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
                .accessibilityIdentifier("energy.planBand")
            if log.isEmpty {
                Text("— \(JIMissingReason.noData.rawValue)").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .padding(.vertical, 8)
            }
            ForEach(log, id: \.date) { day in
                row(day)
                if day.date != log.last?.date { Divider().overlay(theme.color(.hairlineNested)) }
            }
        }
    }

    private func row(_ day: EnergyDay) -> some View {
        let status = energyDayStatus(intake: day.kcalConsumed, goal: goal, deficit: day.deficitCorrected)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                dateText(day).frame(minWidth: 56, alignment: .leading)
                kcalText(day)
                Spacer(minLength: 8)
                statusText(status)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { dateText(day); kcalText(day) }
                statusText(status)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(energyLogDateLabel(day.date))
        .accessibilityValue("\(day.kcalConsumed.map { "\(jiNumber($0, 0)) kcal" } ?? JIMissingReason.noData.rawValue), \(status.word)")
        .accessibilityIdentifier("energy.day.\(day.date)")
    }

    private func dateText(_ day: EnergyDay) -> some View {
        Text(energyLogDateLabel(day.date)).jiFont(.body).foregroundStyle(theme.color(.muted))
    }

    private func kcalText(_ day: EnergyDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(jiValueText(day.kcalConsumed, decimals: 0)).jiFont(.statValue, weight: .bold)
                .foregroundStyle(theme.color(day.kcalConsumed == nil ? .muted : nutritionKcalTintRole))
            if day.kcalConsumed != nil { Text("kcal").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
        }
    }

    /// A missing day already starts with "—", so it carries no second dash glyph.
    @ViewBuilder
    private func statusText(_ status: EnergyDayStatus) -> some View {
        if case .missing = status {
            Text(status.word).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(status.role))
        } else {
            Label(status.word, systemImage: status.symbolName)
                .jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(status.role))
        }
    }
}
