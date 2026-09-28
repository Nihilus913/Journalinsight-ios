import SwiftUI
import JICore
import JIDesign

/// B-57 W1: the Goals "Training plan" supporting-target row copy.
public nonisolated let goalsTrainingPlanTitle = "Training plan"
public nonisolated let goalsTrainingPlanSubtitle = "Full Upper ×4 · intervals · Z2 · 10K"

/// B-57 W5 Goals "Training plan": "2 of 4" (done this week of the sessions in the cached plan)
/// + a status word; no week (nothing cached yet) → "—" + "No data", never a fixed "of 4".
public nonisolated func goalsTrainingPlanValue(_ week: TrainingWeekSummary?) -> (count: String, status: String) {
    guard let week, week.planTotal > 0 else { return ("—", JIMissingReason.noData.rawValue) }
    let count = "\(week.planDone.map(String.init) ?? "—") of \(week.planTotal)"
    if !week.matchesPlan { return (count, "\(week.planTotal - week.assigned) to assign") }
    if let done = week.planDone, done >= week.planTotal { return (count, "Done") }
    return (count, "On plan")
}

/// Status words on the supporting-target rows that read as "on track" (the green status role).
nonisolated let goalsOnTrackStatuses: Set<String> = ["On goal", "On plan", "Done"]

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
    /// "On goal" / "Below goal" / "Above goal"; nil when there is nothing to compare.
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
        if value < goal * (1 - band) { return "Below goal" }
        if !floorOnly, value > goal * (1 + band) { return "Above goal" }
        return "On goal"
    }

    /// Grouped like every Targets number ("1,617", W-TGT fixer 2 R3).
    private static func int(_ v: Double?) -> String? { v.flatMap { $0.isFinite ? targetsNumber($0.rounded(), 0) : nil } }

    /// B-73 (W-B57-W2 fixer GOALS-HUB-SEED): Calories and Protein compare against the user's own
    /// goals (`macros`, PrefStore `goals.macros`), never the hub document's seeded nutrition
    /// (`goals.nutrition` is the TEMP bridge until B-50). Unset = "Set your goal", no status.
    /// B-57 W5: the week from the cached plan (`EnvironmentValues.trainingWeekSummary`).
    static func trainingPlanRow(_ week: TrainingWeekSummary?) -> GoalsTargetRow {
        let v = goalsTrainingPlanValue(week)
        guard let week, week.planTotal > 0 else {
            return GoalsTargetRow(title: goalsTrainingPlanTitle, subtitle: goalsTrainingPlanSubtitle, value: "— \(v.status)", status: nil)
        }
        return GoalsTargetRow(title: goalsTrainingPlanTitle, subtitle: goalsTrainingPlanSubtitle, value: v.count, status: v.status)
    }

    public static func targets(goals: Goals?, macros: MacroGoals?, yesterdayKcal: Double?, yesterdayProteinG: Double?,
                               yesterdaySteps: Double?, week: TrainingWeekSummary? = nil) -> [GoalsTargetRow] {
        let missing = "— \(JIMissingReason.noData.rawValue)"
        let noGoal = "No goal set"
        let kcalGoal = macros?.targetKcal, proteinGoal = macros?.proteinG
        var rows: [GoalsTargetRow] = [
            GoalsTargetRow(title: "Calories", subtitle: int(kcalGoal).map { "goal \($0) a day" } ?? MacroGoals.setGoalCopy,
                           value: int(yesterdayKcal).map { "\($0) kcal" } ?? missing,
                           status: status(yesterdayKcal, goal: kcalGoal, floorOnly: false)),
            GoalsTargetRow(title: "Protein", subtitle: int(proteinGoal).map { "goal \($0) g a day" } ?? MacroGoals.setGoalCopy,
                           value: int(yesterdayProteinG).map { "\($0) g" } ?? missing,
                           status: status(yesterdayProteinG, goal: proteinGoal, floorOnly: true)),
            trainingPlanRow(week),
        ]
        for s in goals?.strength ?? [] {
            rows.append(GoalsTargetRow(title: s.exercise.prefix(1).uppercased() + s.exercise.dropFirst(), subtitle: "goal", value: "\(kg(s.targetKg)) kg", status: nil))
        }
        let stepsGoal = goals?.stepsDaily.map(Double.init)
        rows.append(GoalsTargetRow(title: "Daily steps", subtitle: int(stepsGoal).map { "goal \($0) a day" } ?? noGoal,
                                   value: int(yesterdaySteps) ?? missing,
                                   status: status(yesterdaySteps, goal: stepsGoal, floorOnly: true)))
        return rows
    }
}

/// W-FIX5 fixer (Goals-stale): the goals document the shell shows — the result of this session's
/// last successful save when there is one (the hub returned it), else the loaded document.
public nonisolated func goalsShown(hub: Goals?, saved: Goals?) -> Goals? { saved ?? hub }

/// W-TGT L3: the goals the Goals overview shows once the targets document exists — the phone's
/// own weight / steps / nutrition goals (one number per metric; the document is the truth, so a
/// cleared goal stays cleared), the hub document only for the strength targets the phone derives
/// from sessions. No document (nil) = the hub's, as before. No weight goal = a non-finite target,
/// which every reader shows as "no goal" (the hero, More's row). Never a number of its own.
public nonisolated func goalsFromTargets(_ doc: TargetsDocument?, hub: Goals?) -> Goals? {
    guard let doc else { return hub }
    let w = doc.goals.weight
    let weight = WeightGoal(baseKg: w?.baseKg, targetKg: w?.targetKg ?? .nan, targetDate: w?.targetDate)
    let strength = doc.goals.strength.isEmpty ? (hub?.strength ?? []) : doc.goals.strength
    let m = doc.macroGoals
    return Goals(weight: weight, strength: strength, stepsDaily: doc.goals.stepsDaily,
                 nutrition: NutritionGoal(kcalGoal: m.targetKcal, proteinG: m.proteinG, carbsG: m.carbsG, fatG: m.fatG))
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

/// Board 3/05 Goals: hero + supporting targets + "Edit targets" → the Targets editor sheet
/// (W-TGT L3: the weight goal; each supporting row opens its own goal's sheet). The local-only
/// ad-hoc goals (W4-L3, `GoalStore`) are listed underneath only when some exist; the legacy
/// "New goal" form is gone from this screen.
public struct GoalsView: View {
    @Environment(\.jiTheme) private var theme
    /// B-73: the user's own nutrition goals (injected at the app root) — the Calories/Protein rows.
    @Environment(\.nutritionGoals) private var nutritionGoals
    /// B-57 W5: this week's plan (injected by the app shell; nil = unknown → "— No data").
    @Environment(\.trainingWeekSummary) private var week
    /// W-TGT L3: Edit and the supporting rows open the Targets editor sheet (nil = read-only).
    @Environment(\.targetsModel) private var targetsModel
    @State private var editing: TargetSubject?
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
        // W-GUI M4 (mockup 39): the List became cards on the ground — the ONE tinted hero
        // (active weight goal with its progress bar), "Supporting targets · yours" as a grouped
        // card, Edit as a glass pencil, the local goals card, and the "yours to set" caption.
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text("One active goal. Everything else supports it.")
                    .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.bottom, JISpacing.s3)
                if let hero {
                    Surface(level: 1, padding: JISpacing.cardPadding, tint: theme.color(.go)) { heroCard(hero) }
                } else {
                    Surface(level: 1, padding: JISpacing.cardPadding) {
                        Text(board == nil ? "Loading…" : goalsNoHeroText)
                            .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("goals-hero-missing")
                    }
                }
                JISectionHeader("Supporting goals · yours")
                Surface(level: 1, padding: 0) {
                    let rows = GoalsBoard.targets(goals: board?.goals, macros: nutritionGoals.macros, yesterdayKcal: board?.yesterdayKcal,
                                                  yesterdayProteinG: board?.yesterdayProteinG, yesterdaySteps: board?.yesterdaySteps,
                                                  week: week)
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { JIRowDivider().padding(.leading, 0) }
                            if let subject = goalsRowSubject(row.title), let targetsModel {
                                Button { editing = subject } label: {
                                    HStack(spacing: JISpacing.s2) {
                                        targetRow(row)
                                        Image(systemName: JIChevronRowMetrics.chevron).font(.footnote.weight(.semibold))
                                            .foregroundStyle(theme.color(.mutedNested)).accessibilityHidden(true)
                                    }
                                    .padding(.vertical, JISpacing.s3).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens the goal editor")
                            } else {
                                targetRow(row).padding(.vertical, JISpacing.s3)
                            }
                        }
                    }
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
                }
                if !model.goals.isEmpty {
                    JISectionHeader("Your own goals")
                    Surface(level: 1, padding: JISpacing.cardPadding) {
                        VStack(alignment: .leading, spacing: JISpacing.s3) {
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
                Text(goalsYoursCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s4)
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiGlassBackButton()
        .jiTheme(.native)
        .navigationTitle("Goals")
        .toolbar {
            // W-TGT L3: Edit opens the Targets editor (the weight goal); Goals setup is not an entry
            // any more (it wrote the hub's read-only /planning/goals).
            if targetsModel != nil {
                ToolbarItem(placement: .primaryAction) {
                    JIGlassButton("pencil", label: "Edit goals") { editing = .goal(.weight) }
                    .accessibilityIdentifier("goals-edit-targets")
                }
            }
        }
        .sheet(item: $editing) { subject in
            if let targetsModel {
                TargetEditorSheet(subject: subject, document: targetsModel.document) { next in await targetsModel.save(next) }
            }
        }
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
                Text(board?.latestKg.map { String(format: "%.1f", $0) } ?? hero.startText.replacingOccurrences(of: " kg", with: ""))
                    .jiNumeral(.numeralLarge, weight: .heavy, tint: .text)
                Text("→ \(hero.targetText) kg").jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
            }
            // W-GUI M4 (mockup 39): start → latest → goal as a bar; no bar without the three numbers.
            if let f = goalsProgressFraction(startText: hero.startText, latestKg: board?.latestKg, targetText: hero.targetText) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.color(.nested))
                        Capsule().fill(theme.color(.go)).frame(width: max(4, CGFloat(f) * g.size.width))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                HStack {
                    Text("start \(hero.startText)").jiFont(.micro).foregroundStyle(theme.color(.muted))
                    Spacer()
                    Text("goal \(hero.targetText)").jiFont(.micro).foregroundStyle(theme.color(.muted))
                }
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
                    Text(status).jiFont(.caption).foregroundStyle(theme.color(goalsOnTrackStatuses.contains(status) ? .go : .reduced))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(row.title == goalsTrainingPlanTitle ? "goals-training-plan" : "goals-target-\(row.title)")
    }
}


/// W-TGT L3: the goal a supporting row edits (nil = not a typed goal: training plan, strength).
public nonisolated func goalsRowSubject(_ title: String) -> TargetSubject? {
    switch title {
    case "Calories": .goal(.kcal)
    case "Protein": .goal(.protein)
    case "Daily steps": .goal(.steps)
    default: nil
    }
}

// MARK: - W-GUI M4 (mockup 39) pure helpers

/// The hero's place when no weight goal is set (spec copy rule: "goal", never "target").
public nonisolated let goalsNoHeroText = "No active goal — set one with Edit goals."

public nonisolated let goalsYoursCaption = "Goals are yours to set; the app never seeds them. Where none is set the screens show \u{201C}no goal\u{201D}."

/// How far from the start weight to the target the latest reading sits (0…1); nil when any of
/// the three is missing or the start equals the target (no bar against a guess).
public nonisolated func goalsProgressFraction(startText: String, latestKg: Double?, targetText: String) -> Double? {
    guard let latest = latestKg, latest.isFinite,
          let start = Double(startText.replacingOccurrences(of: " kg", with: "")),
          let target = Double(targetText), start != target else { return nil }
    return min(1, max(0, (start - latest) / (start - target)))
}
