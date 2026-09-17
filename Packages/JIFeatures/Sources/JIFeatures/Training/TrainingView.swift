import SwiftUI
import JICore
import JIDesign

/// Training screen (W3a-L3, frozen contract `TrainingView.init(model:)`). Composes the week/day
/// strips, gate summary, session-coach entry, day detail, and lift steppers — oracle:
/// `mobile/app/(tabs)/training.tsx`.
public struct TrainingView: View {
    @Bindable private var model: TrainingViewModel
    @State private var showSessionCoach = false
    public init(model: TrainingViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(JIColor.muted) }
                case .loaded: loaded
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
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
    }

    private var header: some View {
        Text("Training").font(.largeTitle.bold()).foregroundStyle(JIColor.text)
    }

    private var loading: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 90); SkeletonBlock(height: 60); SkeletonBlock(height: 160) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(JIColor.text)
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(JIColor.info)
            }
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrainingDayStrip(daily: model.gate?.daily ?? [], selectedDate: model.selectedDate, onSelect: model.selectDate)
            GateDetailCard(morning: model.morning, gate: model.gate)
            sessionCoachEntry
            TrainingDayDetailCard(date: model.selectedDate, detail: model.dayDetail)
            TrainingWeekStrip(exercises: model.exercises)
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
                        Text("LIVE SESSION COACH").font(.caption2.weight(.semibold)).foregroundStyle(JIColor.muted)
                        Text("Session coach").font(.subheadline.weight(.bold)).foregroundStyle(JIColor.text)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(JIColor.muted)
                }
            }
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel("Session coach")
    }
}
