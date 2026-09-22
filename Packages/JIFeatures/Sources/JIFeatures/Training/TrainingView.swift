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
                // B-45 (a): the screen's own date is the REAL device day (mirrors
                // `TodayView`), so Training never reads as "Monday" because the hub's last
                // verdict was written on Monday. The hub's `verdict_date` stays where it
                // belongs — inside the Readiness card, labelled as the verdict's date.
                Text(model.todayDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .jiFont(.subheadline, weight: .semibold)
                    .foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("training-date-header")
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
        .toolbar {
            if sendToWatch != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSendToWatch = true } label: { Label("Send to Watch", systemImage: "applewatch.radiowaves.left.and.right") }
                        .accessibilityLabel("Send to Watch")
                        .accessibilityIdentifier("training-send-to-watch")
                }
            }
        }
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
            TrainingDayStrip(daily: model.gate?.daily ?? [], selectedDate: model.selectedDate, onSelect: model.selectDate)
            JISectionHeader("Readiness")
            // §8.1: the gate hero and the session-coach entry compose side by side in regular
            // width (Pro Max landscape, Stage Manager) and stack on an iPhone. Same two cards.
            AdaptiveHStack {
                GateDetailCard(morning: model.morning, gate: model.gate, isStale: model.verdictIsStale)
                sessionCoachEntry
            }
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
                onAssign: { assigningSession = $0 }
            )
            LiftSteppers(exercises: model.exercises, pendingIds: model.pendingUpdates, failedIds: model.updateFailed) { exercise, patch in
                Task { await model.updateExercise(exerciseId: exercise.exerciseId, exerciseName: exercise.exerciseName, patch: patch) }
            }
        }
    }

    /// The oracle's `SessionCoachEntry` opens `app/session-coach.tsx` — W3b-L1 wires the push.
    private var sessionCoachEntry: some View {
        Button { showSessionCoach = true } label: {
            Surface {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LIVE SESSION COACH").jiFont(.micro, weight: .semibold).foregroundStyle(theme.color(.muted))
                        Text("Session coach").jiFont(.subheadline, weight: .bold).foregroundStyle(theme.color(.text))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(theme.color(.muted))
                }
            }
        }
        .buttonStyle(.pressableScale)
        // Oracle `SessionCoachEntry.tsx` L24 label, verbatim.
        .accessibilityLabel("Open live session coach")
        .accessibilityIdentifier("session-coach-entry")
    }
}
