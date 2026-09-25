import SwiftUI
import JICore
import JIDesign

/// Training screen (W3a-L3, frozen contract `TrainingView.init(model:)`). Composes the week/day
/// strips, gate summary, session-coach entry, day detail, and lift steppers — oracle:
/// `mobile/app/(tabs)/training.tsx`.
public struct TrainingView: View {
    @Bindable private var model: TrainingViewModel
    @State private var showSessionCoach = false
    /// B-45 (c): the plan session whose weekday the assign sheet is editing; nil = sheet closed.
    @State private var assigningSession: AssignWeekdaySheet.Session?
    /// B-33: a screen root's own token reads resolve to the theme it installs below —
    /// `.jiTheme(.native)` applies to descendants, never to the view that applies it, so reading
    /// `\.jiTheme` here would see the presenter's value rather than this screen's.
    private let theme = JITheme.native
    #if canImport(WorkoutKit)
    // B-37-L3 (P-workouts): the app wires `\.sendToWatchModel`; nil (previews, tests, no hub) hides
    // the toolbar button. Environment-routed so `init(model:)` stays the frozen contract.
    @Environment(\.sendToWatchModel) private var sendToWatch
    @State private var showSendToWatch = false
    #endif
    public init(model: TrainingViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // B-45 (a): the screen's own date is the REAL device day (mirrors `TodayView`).
                // W-FIX3 fixer BUG-44 (board 3/01): "Full · Wed 23 Sep" + the synced pill on one row;
                // the verdict word leads only when the hub's verdict is today's.
                TrainingSessionHeader(
                    subtitle: trainingSubtitle(verdict: model.morning?.verdict, isStale: model.verdictIsStale, date: model.todayDate),
                    fetchedAt: model.fetchedAt, watchLine: watchLine)
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                        .accessibilityIdentifier("training-empty")
                case .loaded: loaded
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .jiTheme(.native)
        // §5: the hand-drawn large title becomes the system one, so scroll-edge and the
        // large-title collapse come from the navigation stack instead of a `VStack` header.
        .navigationTitle("Training")
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        // W-FIX2 BUG-25: the pending glyph clears after ANY drain — on every appearance, and while
        // a weekday is queued and the screen is up (the watcher ends once nothing is pending).
        .onAppear { model.screenAppeared() }
        .task(id: model.pendingSessionSync.isEmpty) { await model.watchPendingSync() }
        .animation(JIMotion.standard, value: model.phase)
        // W3b-L1 (P-session-coach): `TrainingView.init(model:)` is a frozen contract and
        // `TrainingViewModel` (not this lane's file) has no accessor onto its private hub
        // provider, so this pushes with `provider: nil` — which resolves to the same "not
        // available" state a real `HubDataProvider` cast would produce today anyway (it
        // deliberately never conforms to `LiveSessionProviding` — see JICore's doc comment).
        // Wiring the real provider through is a follow-up once `TrainingViewModel` exposes one.
        .navigationDestination(isPresented: $showSessionCoach) {
            SessionCoachView(model: SessionCoachViewModel(provider: nil))
        }
        #if canImport(WorkoutKit)
        .sheet(isPresented: $showSendToWatch) {
            if let sendToWatch { SendToWatchSheet(model: sendToWatch) }
        }
        #endif
        // B-45 (c): "Assign to weekday" — one plan session, one weekday, one PUT.
        .sheet(item: $assigningSession) { session in
            AssignWeekdaySheet(
                session: session,
                isSaving: model.pendingSessionAssign.contains(session.id),
                didFail: model.sessionAssignFailed.contains(session.id)
            ) { weekday in
                Task {
                    await model.assignSession(sessionId: session.id, sessionName: session.name, weekday: weekday)
                    if !model.sessionAssignFailed.contains(session.id) { assigningSession = nil }
                }
            }
        }
    }

    private var watchLine: String? {
        #if canImport(WorkoutKit)
        trainingWatchLine(sendToWatch?.state)
        #else
        nil
        #endif
    }

    private var loading: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 90); SkeletonBlock(height: 60); SkeletonBlock(height: 160) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("training-error")
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("training-retry")
            }
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 16) {
            // W-FIX3 fixer BUG-44 (board 3/01): the hero carries the session, its exercises, Send to
            // Watch and Start session (the live session coach — no separate coach row).
            TrainingHeroCard(
                dayLabel: heroDayLabel,
                sessionName: model.plannedSessionForSelectedDay?.name,
                rows: trainingHeroRows(exercises: model.exercises, session: model.plannedSessionForSelectedDay),
                onSendToWatch: sendToWatchAction,
                onStart: { showSessionCoach = true })
            TrainingDayStrip(daily: model.gate?.daily ?? [], selectedDate: model.selectedDate, onSelect: model.selectDate)
            JISectionHeader("Readiness")
            GateDetailCard(morning: model.morning, gate: model.gate, isStale: model.verdictIsStale)
            JISectionHeader("This day")
            TrainingDayDetailCard(
                date: model.selectedDate,
                detail: model.dayDetail,
                plannedSession: model.plannedSessionForSelectedDay
            )
            JISectionHeader("Plan")
            TrainingWeekStrip(
                exercises: model.exercises,
                highlightedWeekday: model.selectedPlanWeekday,
                planSessions: model.planSessions,
                pendingSync: model.pendingSessionSync,
                onAssign: { assigningSession = $0 }
            )
            LiftSteppers(exercises: model.exercises, pendingIds: model.pendingUpdates, failedIds: model.updateFailed) { exercise, patch in
                Task { await model.updateExercise(exerciseId: exercise.exerciseId, exerciseName: exercise.exerciseName, patch: patch) }
            }
        }
    }

    /// "Today" for the device day, else the selected day's date ("Thu 24 Sep").
    private var heroDayLabel: String {
        guard model.selectedDate != model.todayDateString, let date = trainingStripDate(model.selectedDate) else { return "Today" }
        return date.formatted(Date.FormatStyle(timeZone: trainingStripCalendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
    }

    private var sendToWatchAction: (() -> Void)? {
        #if canImport(WorkoutKit)
        sendToWatch == nil ? nil : { showSendToWatch = true }
        #else
        nil
        #endif
    }
}
