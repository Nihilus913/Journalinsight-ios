import SwiftUI
import JICore
import JIDesign

/// B-57 W1: the Goals "Training plan" supporting-target row copy.
public nonisolated let goalsTrainingPlanTitle = "Training plan"
public nonisolated let goalsTrainingPlanSubtitle = "Full Upper ×4 · intervals · Z2 · 10K"

/// W-FIX2 BUG-41 (board 3/05) — the Goals screen's pure content. "One active goal. Everything else
/// supports it.": the hub goals document's weight goal as the hero (start → target by date, pace
/// from the 7-day energy balance), then the supporting targets. Missing inputs are "—" + a reason.
public nonisolated struct GoalsHero: Sendable, Equatable {
    public let kind: String, byLine: String?, startText: String, targetText: String
    /// "On pace" / "Behind pace"; nil when the pace cannot be computed.
    public let paceStatus: String?
    public let paceLine: String
}

public nonisolated struct GoalsTargetRow: Sendable, Equatable, Identifiable {
    public let title: String, subtitle: String, value: String
    /// "On target" / "Below target" / "Above target"; nil when there is nothing to compare.
    public let status: String?
    public var id: String { title }
}

public nonisolated enum GoalsBoard {
    /// kcal per kg of body mass — the energy-balance convention the Energy screen uses.
    static let kcalPerKg = 7700.0
    static let minTrackingDays = 4

    private static func day(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(iso.prefix(10)))
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private static func kg(_ v: Double) -> String { String(format: "%.1f", v) }

    public static func hero(goals: Goals?, latestKg: Double?, avgDeficit7d: Double?, trackingDays: Int, today: String) -> GoalsHero? {
        guard let w = goals?.weight, w.targetKg.isFinite, w.targetKg > 0 else { return nil }
        let reduce = (w.baseKg ?? latestKg ?? w.targetKg) >= w.targetKg
        let targetDate = w.targetDate.flatMap(day)
        let byLine = targetDate.map { "by \(short($0))" }
        let startText = w.baseKg.map { "\(kg($0)) kg" } ?? "— kg"
        let noPace = GoalsHero(kind: reduce ? "ACTIVE · REDUCE WEIGHT" : "ACTIVE · GAIN WEIGHT", byLine: byLine, startText: startText,
                               targetText: kg(w.targetKg), paceStatus: nil,
                               paceLine: "Pace — \(JIMissingReason.noData.rawValue)")
        guard let latest = latestKg, latest.isFinite, latest > 0, let deficit = avgDeficit7d, deficit.isFinite,
              trackingDays >= minTrackingDays, let targetDate, let now = day(today) else { return noPace }
        let daysLeft = targetDate.timeIntervalSince(now) / 86_400
        guard daysLeft > 0 else { return noPace }
        let projected = latest - deficit * daysLeft / kcalPerKg
        let perWeek = abs(latest - w.targetKg) / (daysLeft / 7)
        let onPace = reduce ? projected <= w.targetKg + 0.05 : projected >= w.targetKg - 0.05
        let line = "At \(energyHeroNumeral(deficit)) kcal a day you land near \(kg(projected)) kg on \(short(targetDate)). "
            + "Hitting \(kg(w.targetKg)) needs about \(kg(perWeek)) kg a week."
        return GoalsHero(kind: noPace.kind, byLine: byLine, startText: startText, targetText: noPace.targetText,
                         paceStatus: onPace ? "On pace" : "Behind pace", paceLine: line)
    }

    private static func status(_ value: Double?, goal: Double?, band: Double = 0.05, floorOnly: Bool) -> String? {
        guard let value, let goal, goal > 0 else { return nil }
        if value < goal * (1 - band) { return "Below target" }
        if !floorOnly, value > goal * (1 + band) { return "Above target" }
        return "On target"
    }

    private static func int(_ v: Double?) -> String? { v.flatMap { $0.isFinite ? String(Int($0.rounded())) : nil } }

    public static func targets(goals: Goals?, yesterdayKcal: Double?, yesterdayProteinG: Double?, yesterdaySteps: Double?) -> [GoalsTargetRow] {
        let missing = "— \(JIMissingReason.noData.rawValue)"
        let noGoal = "No goal set"
        let kcalGoal = goals?.nutrition.kcalGoal, proteinGoal = goals?.nutrition.proteinG
        var rows: [GoalsTargetRow] = [
            GoalsTargetRow(title: "Calories", subtitle: int(kcalGoal).map { "goal \($0) a day" } ?? noGoal,
                           value: int(yesterdayKcal).map { "\($0) kcal" } ?? missing,
                           status: status(yesterdayKcal, goal: kcalGoal, floorOnly: false)),
            GoalsTargetRow(title: "Protein", subtitle: int(proteinGoal).map { "goal \($0) g a day" } ?? noGoal,
                           value: int(yesterdayProteinG).map { "\($0) g" } ?? missing,
                           status: status(yesterdayProteinG, goal: proteinGoal, floorOnly: true)),
            GoalsTargetRow(title: goalsTrainingPlanTitle, subtitle: goalsTrainingPlanSubtitle, value: "— of 4", status: nil),
        ]
        for s in goals?.strength ?? [] {
            rows.append(GoalsTargetRow(title: s.exercise.prefix(1).uppercased() + s.exercise.dropFirst(), subtitle: "target", value: "\(kg(s.targetKg)) kg", status: nil))
        }
        let stepsGoal = goals?.stepsDaily.map(Double.init)
        rows.append(GoalsTargetRow(title: "Daily steps", subtitle: int(stepsGoal).map { "target \($0)" } ?? noGoal,
                                   value: int(yesterdaySteps) ?? missing,
                                   status: status(yesterdaySteps, goal: stepsGoal, floorOnly: true)))
        return rows
    }
}

/// W-FIX2 BUG-41: what More → Goals shows, gathered by the shell from the models it already loads.
public nonisolated struct GoalsBoardInput: Sendable, Equatable {
    public var goals: Goals?
    public var latestKg: Double?
    public var avgDeficit7d: Double?
    public var trackingDays: Int
    public var yesterdayKcal: Double?
    public var yesterdayProteinG: Double?
    public var yesterdaySteps: Double?
    public init(goals: Goals?, latestKg: Double?, avgDeficit7d: Double?, trackingDays: Int,
                yesterdayKcal: Double?, yesterdayProteinG: Double?, yesterdaySteps: Double?) {
        self.goals = goals; self.latestKg = latestKg; self.avgDeficit7d = avgDeficit7d; self.trackingDays = trackingDays
        self.yesterdayKcal = yesterdayKcal; self.yesterdayProteinG = yesterdayProteinG; self.yesterdaySteps = yesterdaySteps
    }
}

/// Board 3/05 Goals: hero + supporting targets + "Edit targets" → GoalsSetup. The local-only
/// ad-hoc goals (W4-L3, `GoalStore`) are listed underneath only when some exist; the legacy
/// "New goal" form is gone from this screen.
public struct GoalsView: View {
    @Environment(\.jiTheme) private var theme
    @Bindable var model: GoalsViewModel
    let now: () -> Date
    let board: GoalsBoardInput?
    let setupModel: GoalsSetupViewModel?

    public init(model: GoalsViewModel, board: GoalsBoardInput? = nil, setupModel: GoalsSetupViewModel? = nil,
                now: @escaping () -> Date = Date.init) {
        self.model = model
        self.board = board
        self.setupModel = setupModel
        self.now = now
    }

    private var todayString: String { String(now().ISO8601Format().prefix(10)) }

    private var hero: GoalsHero? {
        GoalsBoard.hero(goals: board?.goals, latestKg: board?.latestKg, avgDeficit7d: board?.avgDeficit7d,
                        trackingDays: board?.trackingDays ?? 0, today: todayString)
    }

    public var body: some View {
        List {
            Section {
                if let hero { heroCard(hero) } else {
                    Text(board == nil ? "Loading…" : "No active goal — set one in Edit targets.")
                        .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("goals-hero-missing")
                }
            } header: {
                Text("One active goal. Everything else supports it.")
            }
            Section("Supporting targets") {
                ForEach(GoalsBoard.targets(goals: board?.goals, yesterdayKcal: board?.yesterdayKcal,
                                           yesterdayProteinG: board?.yesterdayProteinG, yesterdaySteps: board?.yesterdaySteps)) { row in
                    targetRow(row)
                }
            }
            if let setupModel {
                Section {
                    NavigationLink { GoalsSetupView(model: setupModel) } label: { Text("Edit targets") }
                        .accessibilityIdentifier("goals-edit-targets")
                }
            }
            if !model.goals.isEmpty {
                Section("Your own goals") {
                    ForEach(model.goals) { goal in
                        GoalCard(
                            goal: goal,
                            today: todayString,
                            onStep: { delta in model.setProgress(id: goal.id, progress: goal.progress + delta) },
                            onDelete: { model.deleteGoal(id: goal.id) }
                        )
                    }
                }
            }
        }
        .jiNativeFormChrome()
        .readableColumn()
        .jiTheme(.native)
        .navigationTitle("Goals")
        .task { model.load() }
    }

    private func heroCard(_ hero: GoalsHero) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(hero.kind).jiFont(.footnote, weight: .bold).foregroundStyle(theme.color(.muted))
                Spacer()
                if let by = hero.byLine { Text(by).jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hero.startText).jiFont(.title, weight: .bold).foregroundStyle(theme.color(.text))
                Text("→ \(hero.targetText)").jiFont(.title, weight: .bold).foregroundStyle(theme.color(.text))
            }
            if let status = hero.paceStatus {
                Text(status).jiFont(.subheadline, weight: .semibold)
                    .foregroundStyle(theme.color(status == "On pace" ? .go : .reduced))
            }
            Text(hero.paceLine).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goals-hero")
    }

    private func targetRow(_ row: GoalsTargetRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).jiFont(.body).foregroundStyle(theme.color(.text))
                Text(row.subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.value).jiFont(.body, weight: .semibold)
                    .foregroundStyle(theme.color(row.value.hasPrefix("—") ? .muted : .text))
                if let status = row.status {
                    Text(status).jiFont(.caption).foregroundStyle(theme.color(status == "On target" ? .go : .reduced))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(row.title == goalsTrainingPlanTitle ? "goals-training-plan" : "goals-target-\(row.title)")
    }
}
