import SwiftUI
import JICore
import JIDesign
import JIPersistence
import JIWorkouts

/// The Planner's strength row, as a navigation value (a plan session: id + name + its days).
/// W-B88: `templateId` = the strength day's library workout (HT migration 073) when the row is
/// that template (`t5` → session 1, template 5) — its Garmin push goes by this id.
public nonisolated struct PlannerStrengthRef: Hashable, Identifiable, Sendable {
    public let sessionId: Int?
    public let name: String
    public let weekdays: [Int]
    public let templateId: Int?
    public var id: String { sessionId.map { "s\($0)" } ?? "s:\(name)" }
    public init(sessionId: Int?, name: String, weekdays: [Int], templateId: Int? = nil) {
        self.sessionId = sessionId; self.name = name; self.weekdays = weekdays; self.templateId = templateId
    }
    public init(_ row: PlannerWorkout) {
        self.init(sessionId: row.strengthSessionId ?? row.sessionId, name: row.name, weekdays: row.weekdays, templateId: row.templateId)
    }

    /// The session as the logger and the Watch plan take it (weekday = its day, or −1 when none).
    var plannedSession: PlannedSession { PlannedSession(id: sessionId ?? 0, name: name, weekday: weekdays.first ?? -1) }
}

/// W-B88: a row opens the strength detail (not the editor) when it is a strength plan session, or
/// a strength template linked to one (a strength day as its library workout, `editable` false).
public nonisolated func plannerOpensStrengthDetail(_ row: PlannerWorkout) -> Bool {
    if row.kind == .planSession { return true }
    return row.strengthSessionId != nil && !row.editable
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

/// W-B88 fix (B88-5 tap path): what the detail's "Send to Watch" sheet shows — the strength day's
/// workout by name and its lifts — and what Send sends: the Watch strength plan for the linked
/// session (WorkoutKit has no strength type, so the template id is not a Watch path; the template
/// id is the Garmin push's). Pure, so the sheet and its test read the same rows.
public nonisolated struct PlannerStrengthSendSummary: Equatable, Sendable {
    public struct Line: Equatable, Sendable { public let name: String; public let detail: String }
    public let title: String
    public let lines: [Line]
    public let planSessionId: Int?
    public let templateId: Int?
    public var canSend: Bool { !lines.isEmpty }
    public init(ref: PlannerStrengthRef, lifts: [StrengthLogLift]) {
        title = ref.name
        lines = lifts.map { Line(name: $0.exerciseKey, detail: plannerLiftLine($0)) }
        planSessionId = ref.sessionId
        templateId = ref.templateId
    }
}

/// W-PLANNER PL-4 — a strength session from the Planner's ALL WORKOUTS: its lifts and next weights,
/// "Log sets" (the A-10 logger over THIS session) and "Send to Watch" (this session as the Watch's
/// strength plan for today, W-B38-B). Its day is changed from THIS WEEK (tap or drag).
/// W-B88: opened from a strength day's template row too (same session); + "Push to Garmin Connect"
/// for that template (its strength segment, built by the hub from these lifts).
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
    @State private var showSendSheet = false
    private let theme = JITheme.native

    /// W-B88: the strength day's library workout (HT migration 073), when the row was that template.
    private var template: WorkoutTemplate? {
        ref.templateId.flatMap { id in model.library?.templates.first { $0.templateId == id } }
    }

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
                        Button { sentToWatch = false; showSendSheet = true } label: { Label("Send to Watch", systemImage: "applewatch.radiowaves.left.and.right") }
                            .buttonStyle(.jiSecondary)
                            .disabled(lifts.isEmpty)
                            .accessibilityIdentifier("planner-send-to-watch")
                    }
                    // W-B88: the strength day IS a library workout (template id) — Garmin push by that id.
                    if let t = template, let library = model.library {
                        Button { Task { await library.pushToGarmin(t) } } label: {
                            Label(library.pushDisabledReason(for: t) ?? "Push to Garmin Connect", systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(.jiSecondary)
                        .disabled(library.pushDisabledReason(for: t) != nil)
                        .accessibilityIdentifier("planner-push-garmin")
                        if let n = library.notice {
                            Text(n.text).jiFont(.footnote).foregroundStyle(theme.color(n.isError ? .danger : .muted))
                                .accessibilityIdentifier("planner-push-garmin-notice")
                        }
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
        .sheet(isPresented: $showSendSheet) { sendSheet(PlannerStrengthSendSummary(ref: ref, lifts: lifts)) }
    }

    /// The Send to Watch sheet: the day's workout by name, its lifts, Send (the Watch strength plan).
    private func sendSheet(_ summary: PlannerStrengthSendSummary) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(summary.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.name).foregroundStyle(theme.color(.text))
                            Spacer(minLength: JISpacing.s2)
                            Text(line.detail).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("planner-send-sheet-lift")
                    }
                } header: {
                    Text(summary.title).accessibilityIdentifier("planner-send-sheet-title")
                } footer: {
                    Text("Sent as today's strength session — the Watch logs each set.")
                }
                if sentToWatch {
                    Section {
                        Label("On your Watch as today's strength session.", systemImage: "checkmark.applewatch")
                            .foregroundStyle(theme.color(.go))
                            .accessibilityIdentifier("planner-sent-to-watch")
                    }
                }
            }
            #if os(iOS)
            .jiNativeFormChrome()
            #endif
            .jiSheetGround()
            .navigationTitle("Send to Watch")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sentToWatch ? "Done" : "Close") { showSendSheet = false }
                        .accessibilityIdentifier("planner-send-sheet-close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { sendToWatch() }
                        .disabled(!summary.canSend || sentToWatch)
                        .accessibilityLabel("Send \(summary.title) to Watch")
                        .accessibilityIdentifier("planner-send-sheet-send")
                }
            }
        }
        .accessibilityIdentifier("planner-send-sheet")
        .jiTheme(.native)
        #if os(iOS)
        .presentationSizing(.form)
        #endif
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
                                           today: { today }, restAlert: .live, reminders: deps.reminders)
        // B-43 P1 rest-end alert permission; RG-76: a denial is kept as the logger's 'Notifications off' state.
        if let log = strengthLog { Task { await log.requestRestAlertPermission() } }
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
