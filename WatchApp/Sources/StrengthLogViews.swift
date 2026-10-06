import SwiftUI
import JIDesign
import JICompute
import JIWorkouts

// W-B38-B B-4/B-5/B-6: the Watch strength logger. Exercise list (start / end the session, HR vs
// the cap) → set entry (Crown weight in the exercise's step, reps, RPE; Double Tap = Log set) →
// rest / timed-set countdown. Native watchOS controls (decision: native UI, no mock pass).

/// Root of the strength page — the 4th page next to the three glances.
struct StrengthLogRoot: View {
    let composition: StrengthLogComposition
    var body: some View {
        NavigationStack {
            StrengthExerciseList(model: composition.model)
        }
        .onChange(of: composition.model.controller.state) { composition.sessionStateChanged() }
        .onChange(of: composition.model.controller.isMirrored) { composition.sessionStateChanged() }
    }
}

struct StrengthExerciseList: View {
    @Bindable var model: StrengthLogViewModel
    @Environment(\.jiTheme) private var theme

    var body: some View {
        List {
            Section {
                StrengthCapGauge(model: model)
                sessionButton
                if model.restAlertsOff {
                    Text(RestEndAlert.offNotice).jiFont(.micro).foregroundStyle(theme.color(.muted))
                }
            }
            if model.exercises.isEmpty {
                Text("Open today's training on your iPhone to send the plan here.")
                    .jiFont(.micro).foregroundStyle(theme.color(.muted))
            } else {
                Section(model.bridge.plan?.title ?? "Today") {
                    ForEach(model.exercises) { ex in
                        NavigationLink {
                            StrengthSetEntry(model: model)
                                .onAppear { if model.selected?.exerciseKey != ex.exerciseKey { model.select(ex) } }
                        } label: {
                            StrengthExerciseRow(exercise: ex, done: model.sets(for: ex).count)
                        }
                    }
                }
            }
            if let error = model.controller.errorMessage {
                Text(error).jiFont(.micro).foregroundStyle(theme.color(.danger))
            }
        }
        .navigationTitle("Strength")
    }

    @ViewBuilder private var sessionButton: some View {
        switch model.controller.state {
        case .idle:
            Button("Start session") { Task { await model.startSession() } }
                .tint(theme.color(.info))
        case .running, .paused:
            Button("End session", role: .destructive) { Task { await model.endSession() } }
        case .ending:
            ProgressView()
        case .ended:
            Label("Saved to Health", systemImage: "checkmark.circle").foregroundStyle(theme.color(.muted))
        }
    }
}

struct StrengthExerciseRow: View {
    let exercise: StrengthWatchExercise
    let done: Int
    @Environment(\.jiTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name).lineLimit(2)
            HStack(spacing: 4) {
                if let target = exercise.targetSets { Text("\(done)/\(target) sets") } else { Text("\(done) sets") }
                if let muscle = exercise.muscle { Text("· \(muscle)") }
            }
            .jiFont(.micro).foregroundStyle(theme.color(.muted))
        }
    }
}

/// Live HR against the session limit (175 cap / no Zone 5). No reading → "No live reading",
/// never a 0.
struct StrengthCapGauge: View {
    let model: StrengthLogViewModel
    @Environment(\.jiTheme) private var theme

    var body: some View {
        let state = model.capState
        HStack {
            Gauge(value: Double(min(model.controller.heartRateBpm ?? 0, model.limitBpm)), in: 0...Double(model.limitBpm)) {
                Image(systemName: "heart.fill")
            } currentValueLabel: {
                Text(model.controller.heartRateBpm.map(String.init) ?? "—")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(theme.color(Self.role(state)))
            VStack(alignment: .leading) {
                Text(SessionCap.label(for: state)).font(.footnote)
                Text("Limit \(model.limitBpm) bpm").jiFont(.micro).foregroundStyle(theme.color(.muted))
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func role(_ state: SessionCap.State) -> JIColorRole {
        switch state {
        case .unknown, .noLimit: .muted
        case .under: .go
        case .approaching: .reduced
        case .breach: .danger
        }
    }
}

struct StrengthSetEntry: View {
    @Bindable var model: StrengthLogViewModel
    @State private var crownKg: Double = 0
    @Environment(\.jiTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if model.timer.phase != .idle { StrengthTimerCard(model: model) }
                if let ex = model.selected {
                    if ex.kind == .reps { repsEntry } else { timedEntry }
                    primaryButton(ex)
                    loggedSets(ex)
                }
            }
        }
        .navigationTitle(model.selected?.name ?? "Set")
        .task {
            while !Task.isCancelled {
                await model.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var repsEntry: some View {
        VStack(spacing: 6) {
            HStack {
                Text(model.entryWeightKg.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) kg" } ?? "— kg")
                    .font(.title3.monospacedDigit())
                    .focusable()
                    .digitalCrownRotation($crownKg, from: 0, through: 400, by: model.weightStepKg,
                                          sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                    .onChange(of: crownKg) { model.setCrownWeight(crownKg) }
                    .onAppear { crownKg = model.entryWeightKg ?? 0 }
                    .onChange(of: model.selected?.exerciseKey) { crownKg = model.entryWeightKg ?? 0 }
                    .accessibilityLabel("Weight, turn the Digital Crown")
            }
            Stepper(value: Binding(get: { model.entryReps ?? 0 }, set: { model.entryReps = $0 > 0 ? $0 : nil }), in: 0...50) {
                Text(model.entryReps.map { "\($0) reps" } ?? "— reps")
            }
            rpePicker
        }
    }

    private var timedEntry: some View {
        VStack(spacing: 6) {
            Stepper(value: Binding(get: { model.entryDurationS ?? 0 }, set: { model.entryDurationS = $0 > 0 ? $0 : nil }),
                    in: 0...600, step: 5) {
                Text(model.entryDurationS.map { "\($0) s" } ?? "— s")
            }
            rpePicker
        }
    }

    private var rpePicker: some View {
        Picker("RPE", selection: Binding(get: { model.entryRpe ?? 0 }, set: { model.entryRpe = $0 > 0 ? $0 : nil })) {
            Text("RPE —").tag(0.0)
            ForEach([6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0], id: \.self) { Text("RPE \($0.formatted())").tag($0) }
        }
    }

    @ViewBuilder private func primaryButton(_ ex: StrengthWatchExercise) -> some View {
        let title: String = {
            if model.editingSetId != nil { return "Save set" }
            if ex.kind == .timed { return model.timer.phase == .timedSet ? "Stop" : "Start \(model.entryDurationS ?? 0) s" }
            return "Log set"
        }()
        Button(title) { Task { await model.primaryAction() } }
            .buttonStyle(.borderedProminent)
            .tint(theme.color(.info))
            .disabled(!(model.canLog || model.timer.phase == .timedSet))
            .handGestureShortcut(.primaryAction) // B-6: Double Tap = Log set
        if !model.isSessionActive {
            Text("Start the session to log sets.").jiFont(.micro).foregroundStyle(theme.color(.muted))
        }
        if let editing = model.editingSetId, let set = model.loggedSets.first(where: { $0.clientId == editing }) {
            Button("Delete set", role: .destructive) { Task { await model.delete(set) } }
            Button("Cancel edit") { model.cancelEdit() }
        }
    }

    @ViewBuilder private func loggedSets(_ ex: StrengthWatchExercise) -> some View {
        ForEach(model.sets(for: ex)) { set in
            HStack {
                Text("Set \(set.setIndex)")
                Spacer()
                Text(Self.summary(set)).monospacedDigit()
            }
            .font(.footnote)
            .contentShape(Rectangle())
            .onTapGesture { model.beginEdit(set) } // tap = edit; "Delete set" shows while editing
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edit this set")
            .accessibilityAction(named: "Delete") { Task { await model.delete(set) } }
        }
    }

    static func summary(_ s: StrengthBridgeSet) -> String {
        if s.kind == .timed { return s.durationS.map { "\($0) s" } ?? "—" }
        let kg = s.weightKg.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) kg" } ?? "BW"
        return "\(kg) × \(s.reps.map(String.init) ?? "—")"
    }
}

/// B-5: rest (auto-started after a logged set; skip / +15 s) or the timed-set countdown.
struct StrengthTimerCard: View {
    let model: StrengthLogViewModel
    @Environment(\.jiTheme) private var theme
    var body: some View {
        VStack(spacing: 4) {
            Text(model.timer.phase == .timedSet ? "Hold" : "Rest").jiFont(.micro).foregroundStyle(theme.color(.muted))
            Text(Self.clock(model.remainingSeconds ?? 0)).font(.title2.monospacedDigit())
            if model.timer.phase == .resting {
                HStack {
                    Button("+15 s") { model.addRest() }
                    Button("Skip") { model.skipRest() }
                }
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity)
    }

    static func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}
