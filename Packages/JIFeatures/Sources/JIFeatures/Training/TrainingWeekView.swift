import SwiftUI
import JICore
import JIDesign

public nonisolated func trainingWeekStatusText(_ s: TrainingWeekSummary) -> String {
    guard s.planTotal > 0 else { return "No plan yet" }
    if s.matchesPlan { return "Matches plan" }
    let open = s.planTotal - s.assigned
    return "\(open) session\(open == 1 ? "" : "s") not on a day yet"
}

/// Interval rows name the user's own cap (W4, optional) — never a default number.
public nonisolated func trainingWeekIntervalCaption(hrCapBpm: Int?) -> String {
    hrCapBpm.map { "Your cap \($0)" } ?? "No cap set"
}

/// Sessions the hub can take a weekday for (a real plan_session id — B-52's rule). MainActor:
/// `AssignWeekdaySheet.Session`'s init is (JIFeatures default isolation).
public func assignableSessions(planSessions: [PlanSessionOut], exercises: [Exercise]) -> [AssignWeekdaySheet.Session] {
    weekSpine(planSessions: planSessions, exercises: exercises).compactMap { e in
        e.id.map { AssignWeekdaySheet.Session(id: $0, name: e.name, weekday: e.weekday) }
    }
}

/// B-57 W5 board 3/02 "Your week". Writes go through `TrainingViewModel.assignSession` (Outbox
/// first, B-52), so each change is saved on tap — there is no separate Save step. A strength day
/// opens its session's weekday sheet; a rest day offers the sessions to put on it; the interval
/// and long-run days follow the morning-call schedule (not assignable until B-40 templates).
public struct TrainingWeekView: View {
    @Bindable private var model: TrainingViewModel
    @State private var editing: AssignWeekdaySheet.Session?
    @State private var pickingFor: Int?
    @Environment(\.gateSettings) private var gateSettings
    /// B-33: a screen root reads the theme it installs (see `TrainingView`).
    private let theme = JITheme.native

    public init(model: TrainingViewModel) { self.model = model }

    private var summary: TrainingWeekSummary { model.weekSummary }
    private var sessions: [AssignWeekdaySheet.Session] { assignableSessions(planSessions: model.planSessions, exercises: model.exercises) }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text("Give each day a session. Training counts what you assign here.")
                    .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.bottom, JISpacing.s3)
                Surface(level: 1, padding: JISpacing.cardPadding, tint: summary.matchesPlan ? theme.color(.go) : nil) { summaryCard }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("training-week-summary")
                JISectionHeader("Sessions")
                Surface(level: 1, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(summary.days) { day in
                            if day.weekday > 0 { JIRowDivider().padding(.leading, 0) }
                            dayRow(day).padding(.vertical, JISpacing.s3)
                        }
                        if summary.days.isEmpty {
                            Text("— No data").jiFont(.body).foregroundStyle(theme.color(.muted))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, JISpacing.s3)
                        }
                    }
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
                }
                Text("The Training count follows these days. Intervals and the long run follow the morning-call schedule for now.")
                    .jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s3)
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiGlassBackButton()
        .jiTheme(.native)
        .navigationTitle("Your week")
        .onAppear { model.screenAppeared() }
        .sheet(item: $editing) { session in
            AssignWeekdaySheet(session: session, isSaving: model.pendingSessionAssign.contains(session.id),
                               didFail: model.sessionAssignFailed.contains(session.id)) { weekday in
                Task {
                    await model.assignSession(sessionId: session.id, sessionName: session.name, weekday: weekday)
                    if !model.sessionAssignFailed.contains(session.id) { editing = nil }
                }
            }
        }
        .confirmationDialog("Put a session on \(pickingFor.map { planWeekdayNames[$0] } ?? "")",
                            isPresented: Binding(get: { pickingFor != nil }, set: { if !$0 { pickingFor = nil } }),
                            titleVisibility: .visible) {
            ForEach(sessions) { s in
                Button(s.weekday.map { "\(s.name) (now \(trainingWeekdayShortNames[$0]))" } ?? s.name) {
                    let day = pickingFor
                    Task { await model.assignSession(sessionId: s.id, sessionName: s.name, weekday: day) }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: JISpacing.s2) {
            Text("STRENGTH DAYS").jiFont(.micro, weight: .bold).foregroundStyle(theme.color(.muted))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary.planTotal > 0 ? "\(summary.assigned)" : "—").jiNumeral(.numeralLarge, weight: .heavy, tint: .text)
                Text(summary.planTotal > 0 ? "of \(summary.planTotal) in your plan" : "No plan yet")
                    .jiFont(.body).foregroundStyle(theme.color(.muted))
            }
            if summary.planTotal > 0 {
                Label(trainingWeekStatusText(summary), systemImage: summary.matchesPlan ? "checkmark" : "exclamationmark.circle")
                    .jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(summary.matchesPlan ? .go : .reduced))
                HStack(spacing: 4) {
                    ForEach(0..<summary.planTotal, id: \.self) { i in
                        Capsule().fill(theme.color(i < summary.assigned ? .go : .nested)).frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowLabel(_ day: TrainingWeekDay, pending: Bool) -> some View {
        HStack(spacing: JISpacing.s3) {
            Text(trainingWeekdayShortNames[day.weekday]).jiFont(.body, weight: day.isToday ? .bold : .regular)
                .foregroundStyle(theme.color(day.isToday ? .text : .muted)).frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.sessionName ?? "Rest").jiFont(.body).foregroundStyle(theme.color(day.kind == .rest ? .muted : .text))
                    .fixedSize(horizontal: false, vertical: true)
                if day.kind == .interval {
                    Text(trainingWeekIntervalCaption(hrCapBpm: gateSettings.hrCapBpm)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                if pending { Text("Waiting to sync").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
            }
            Spacer(minLength: JISpacing.s2)
            Text(day.kind.rawValue).jiFont(.caption, weight: .bold).foregroundStyle(theme.color(.muted))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func dayRow(_ day: TrainingWeekDay) -> some View {
        let pending = day.sessionId.map { model.pendingSessionSync.contains($0) } ?? false
        let label = trainingWeekDayAccessibilityLabel(day) + (pending ? ", waiting to sync" : "")
        switch day.kind {
        case .strength:
            Button {
                if let id = day.sessionId, let s = sessions.first(where: { $0.id == id }) { editing = s }
            } label: { JIChevronRow { rowLabel(day, pending: pending) } }
                .buttonStyle(.plain)
                .disabled(day.sessionId.flatMap { id in sessions.first { $0.id == id } } == nil)
                .accessibilityElement(children: .combine).accessibilityLabel(label)
                .accessibilityIdentifier("training-week-row-\(day.weekday)")
        case .rest:
            Button { pickingFor = day.weekday } label: { JIChevronRow { rowLabel(day, pending: pending) } }
                .buttonStyle(.plain)
                .disabled(sessions.isEmpty)
                .accessibilityElement(children: .combine).accessibilityLabel(label)
                .accessibilityIdentifier("training-week-row-\(day.weekday)")
        case .interval, .longRun:
            rowLabel(day, pending: pending)
                .frame(minHeight: JIChevronRowMetrics.minHeight - 2 * JIChevronRowMetrics.verticalPadding)
                .accessibilityElement(children: .combine).accessibilityLabel(label)
                .accessibilityIdentifier("training-week-row-\(day.weekday)")
        }
    }
}
