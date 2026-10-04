import SwiftUI
import JICore
import JIDesign
import JIPersistence
import JIWorkouts

/// The Planner's strength row, as a navigation value (a plan session: id + name + its days).
public nonisolated struct PlannerStrengthRef: Hashable, Identifiable, Sendable {
    public let sessionId: Int?
    public let name: String
    public let weekdays: [Int]
    public var id: String { sessionId.map { "s\($0)" } ?? "s:\(name)" }
    public init(sessionId: Int?, name: String, weekdays: [Int]) { self.sessionId = sessionId; self.name = name; self.weekdays = weekdays }
    public init(_ row: PlannerWorkout) { self.init(sessionId: row.sessionId, name: row.name, weekdays: row.weekdays) }

    /// The session as the logger and the Watch plan take it (weekday = its day, or −1 when none).
    var plannedSession: PlannedSession { PlannedSession(id: sessionId ?? 0, name: name, weekday: weekdays.first ?? -1) }
}

/// PL-4: a plan session's lifts with the next weights (progression), as the logger would prefill
/// them — pure, so the detail and its test read the same rows.
public nonisolated func plannerStrengthLifts(_ ref: PlannerStrengthRef, exercises: [Exercise], progressions: [LiftProgression]) -> [StrengthLogLift] {
    strengthLogLifts(exercises: exercises, session: ref.plannedSession, progressions: progressions)
}

/// "Next 52.5 kg · 3 × 8" — the parts known (never a zero for a missing weight).
public nonisolated func plannerLiftLine(_ lift: StrengthLogLift) -> String {
    var parts: [String] = []
    if let kg = lift.nextKg ?? lift.currentKg, kg > 0 {
        parts.append("Next " + kg.formatted(.number.precision(.fractionLength(0...1))) + " kg")
    }
    switch (lift.sets, lift.repsTarget) {
    case let (s?, r?): parts.append("\(s) × \(r)")
    case let (s?, nil): parts.append("\(s) sets")
    case let (nil, r?): parts.append("\(r) reps")
    case (nil, nil): break
    }
    return parts.isEmpty ? "—" : parts.joined(separator: " · ")
}

/// W-PLANNER PL-4 — a strength session from the Planner's ALL WORKOUTS: its lifts and next weights,
/// "Log sets" (the A-10 logger over THIS session) and "Send to Watch" (this session as the Watch's
/// strength plan for today, W-B38-B). Its day is changed from THIS WEEK (tap or drag).
struct PlannerStrengthDetail: View {
    @Bindable var model: TrainingViewModel
    let ref: PlannerStrengthRef
    @Environment(\.strengthLogDeps) private var strengthLogDeps
    @Environment(\.progression) private var progression
    @Environment(\.strengthWatchPlanSender) private var sendWatchPlan
    @Environment(\.gateSettings) private var gateSettings
    @State private var strengthLog: StrengthLogViewModel?
    @State private var strengthHistory: StrengthHistoryViewModel?
    @State private var showStrengthLog = false
    @State private var sentToWatch = false
    private let theme = JITheme.native

    private var lifts: [StrengthLogLift] {
        plannerStrengthLifts(ref, exercises: model.exercises, progressions: progression?.lifts ?? [])
    }

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text(ref.weekdays.isEmpty ? "Not on a day — drag it onto a day in the Planner." : "On " + plannerDaysText(ref.weekdays))
                    .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.bottom, JISpacing.s3)
                    .accessibilityIdentifier("planner-strength-days")
                JISectionHeader("Lifts")
                Surface(level: 1, padding: 0) {
                    VStack(spacing: 0) {
                        if lifts.isEmpty {
                            Text("No lifts in this session yet.").jiFont(.body).foregroundStyle(theme.color(.muted))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, JISpacing.s3)
                        }
                        ForEach(Array(lifts.enumerated()), id: \.offset) { i, lift in
                            if i > 0 { JIRowDivider().padding(.leading, 0) }
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline) { liftName(lift); Spacer(minLength: JISpacing.s2); liftValue(lift) }
                                VStack(alignment: .leading, spacing: 2) { liftName(lift); liftValue(lift) }
                            }
                            .padding(.vertical, JISpacing.s3)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
                }
                .accessibilityIdentifier("planner-strength-lifts")
                VStack(spacing: JISpacing.s3) {
                    if strengthLogDeps != nil {
                        Button("Log sets") { openStrengthLog() }
                            .buttonStyle(.jiPrimary)
                            .accessibilityIdentifier("planner-log-sets")
                    }
                    if sendWatchPlan != nil {
                        Button { sendToWatch() } label: { Label("Send to Watch", systemImage: "applewatch.radiowaves.left.and.right") }
                            .buttonStyle(.jiSecondary)
                            .disabled(lifts.isEmpty)
                            .accessibilityIdentifier("planner-send-to-watch")
                    }
                    if sentToWatch {
                        Text("On your Watch as today's strength session.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .accessibilityIdentifier("planner-sent-to-watch")
                    }
                }
                .padding(.top, JISpacing.s4)
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiGlassBackButton()
        .jiTheme(.native)
        .navigationTitle(ref.name)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("planner-strength-detail")
        .navigationDestination(isPresented: $showStrengthLog) {
            if let strengthLog { StrengthLogView(model: strengthLog, history: strengthHistory) }
        }
    }

    private func liftName(_ lift: StrengthLogLift) -> some View {
        Text(lift.exerciseKey).jiFont(.subheadline).foregroundStyle(theme.color(.text)).fixedSize(horizontal: false, vertical: true)
    }

    private func liftValue(_ lift: StrengthLogLift) -> some View {
        Text(plannerLiftLine(lift)).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.muted))
    }

    /// The A-10 logger over THIS session (same build as the Training hero's "Log sets").
    private func openStrengthLog() {
        guard let deps = strengthLogDeps else { return }
        let store = StrengthSessionLogStore(db: deps.db)
        let today = model.todayDateString
        strengthLog = StrengthLogViewModel(lifts: lifts, sessionId: ref.sessionId, sessionName: ref.name, store: store,
                                           outbox: Outbox(db: deps.db), provider: deps.provider, prefs: deps.prefs,
                                           today: { today })
        strengthHistory = StrengthHistoryViewModel(store: store, provider: deps.provider, today: { today })
        showStrengthLog = true
    }

    private func sendToWatch() {
        guard let sendWatchPlan, !lifts.isEmpty else { return }
        let today = model.todayDateString
        let store = strengthLogDeps.map { StrengthSessionLogStore(db: $0.db) }
        var last: [String: [StrengthSetLog]] = [:]
        for lift in lifts { last[lift.exerciseKey] = (try? store?.lastSets(exerciseKey: lift.exerciseKey, before: today)) ?? nil }
        sendWatchPlan(StrengthWatchPlanBuilder.plan(date: today, planSessionId: ref.sessionId, title: ref.name, lifts: lifts,
                                                    lastSets: last, settings: gateSettings, restS: 90))
        sentToWatch = true
    }
}
