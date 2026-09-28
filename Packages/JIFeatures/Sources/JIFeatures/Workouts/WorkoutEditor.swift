import SwiftUI
import JICore
import JIDesign

/// W-B40 L2 (B-40b-3, spec §4, mockups row 2 "Edit workout" + "strength + run") — the template
/// editor: a `Form` sheet over `WorkoutEditorViewModel` (Cancel / Save, `onSave` through the
/// library's offline-first queue). One section per part (segment); cardio step rows show purpose,
/// end, target and ×repeat; strength rows show exercise, sets × reps|time, kg, rest. Tapping a
/// step opens its detail form. Existing workouts get Send to Watch (cardio only — strength says
/// why), Push to Garmin (hub-only) and Delete.
public struct WorkoutEditorSheet: View {
    @Bindable private var model: WorkoutEditorViewModel
    private let library: WorkoutLibraryViewModel?
    private let onSendToWatch: ((WorkoutTemplate) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    private let theme = JITheme.native

    public init(model: WorkoutEditorViewModel, library: WorkoutLibraryViewModel? = nil, onSendToWatch: ((WorkoutTemplate) -> Void)? = nil) {
        self.model = model; self.library = library; self.onSendToWatch = onSendToWatch
    }

    public var body: some View {
        NavigationStack {
            form
                .navigationTitle(model.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.accessibilityIdentifier("workout-editor-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { if await model.save() { dismiss() } }
                        } label: {
                            if model.isSaving { ProgressView() } else { Text("Save").bold() }
                        }
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("workout-editor-save")
                    }
                }
                .navigationDestination(for: UUID.self) { id in stepDetail(id) }
        }
        .jiTheme(.native)
        .jiNativeSheetSizing()
    }

    /// §8.5: the form without the navigation shell.
    @ViewBuilder var form: some View {
        Form {
            Section {
                TextField("Name", text: $model.name)
                    .accessibilityIdentifier("workout-editor-name")
                Picker("Where", selection: $model.location) {
                    Text("Outdoor").tag(WorkoutLocation.outdoor)
                    Text("Indoor").tag(WorkoutLocation.indoor)
                }
                TextField("Notes", text: $model.descriptionText, axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("workout-editor-notes")
            }

            Section {
                let days = WorkoutFormat.weekdays(model.weekdays)
                if days.isEmpty {
                    Text("Not on a training day yet").foregroundStyle(theme.color(.muted))
                } else {
                    Text(days.joined(separator: " · ")).foregroundStyle(theme.color(.text))
                }
            } header: {
                Text("Days")
            } footer: {
                Text("Pick the day in Training — tap a day and choose this workout.")
            }

            ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, segment in
                segmentSection(segment, index: index)
            }

            Section {
                Menu {
                    ForEach(WorkoutSport.allCases, id: \.self) { sport in
                        Button { model.addSegment(sport) } label: { Label(WorkoutFormat.sport(sport), systemImage: WorkoutFormat.sportSymbol(sport)) }
                    }
                } label: {
                    Label("Add a part", systemImage: "plus.rectangle.on.rectangle")
                }
                .accessibilityIdentifier("workout-editor-add-part")
            } footer: {
                Text("Heart-rate alerts on the Watch are absolute bpm; a zone is turned into bpm from your own zones when you send it.")
            }

            if !model.validationIssues.isEmpty || model.errorText != nil {
                Section {
                    if let error = model.errorText {
                        Text(error).foregroundStyle(theme.color(.danger)).accessibilityIdentifier("workout-editor-error")
                    }
                    ForEach(model.validationIssues, id: \.self) { issue in
                        Text(issue).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    }
                }
                .accessibilityIdentifier("workout-editor-issues")
            }

            if let original = model.original, original.templateId > 0 || library != nil {
                actionsSection(original)
            }
        }
    }

    private func segmentSection(_ segment: EditableSegment, index: Int) -> some View {
        Section {
            ForEach(segment.steps) { row in
                NavigationLink(value: row.id) { WorkoutStepRow(step: row.step) }
                    .accessibilityIdentifier("workout-editor-step")
            }
            .onDelete { model.removeSteps(at: $0, in: segment.id) }
            .onMove { model.moveSteps(from: $0, to: $1, in: segment.id) }

            if segment.sport == .strength {
                Button { model.addStrengthStep(to: segment.id) } label: { Label("Add exercise", systemImage: "plus") }
                Button { model.addCardioStep(to: segment.id, purpose: .warmup) } label: { Label("Add warm-up", systemImage: "plus") }
            } else {
                Button { model.addCardioStep(to: segment.id) } label: { Label("Add step", systemImage: "plus") }
                    .accessibilityIdentifier("workout-editor-add-step")
            }
        } header: {
            HStack {
                Text(segmentTitle(segment, index: index))
                Spacer()
                if model.segments.count > 1 {
                    Menu {
                        Button(role: .destructive) { model.removeSegment(segment.id) } label: { Label("Remove this part", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel("Part options")
                    }
                }
            }
        } footer: {
            if segment.sport == .strength {
                Text("Strength is not sent to the Apple Watch — sets are logged in JournalInsight.")
            }
        }
    }

    private func segmentTitle(_ s: EditableSegment, index: Int) -> String {
        let seg = WorkoutSegment(sport: s.sport, steps: s.steps.map(\.step))
        let time = WorkoutFormat.timedSeconds(seg).map { " · " + WorkoutFormat.duration(seconds: $0) } ?? ""
        let name = s.sport == .strength ? "Strength" : "Steps"
        return model.segments.count > 1 ? "Part \(index + 1) · \(WorkoutFormat.sport(s.sport))\(time)" : "\(name)\(time)"
    }

    @ViewBuilder private func actionsSection(_ template: WorkoutTemplate) -> some View {
        Section {
            if let onSendToWatch {
                Button { onSendToWatch(template) } label: { Label("Send to Watch…", systemImage: "applewatch") }
                    .disabled(model.watchDisabledReason != nil)
                    .accessibilityIdentifier("workout-editor-send-watch")
            }
            if let library {
                Button { Task { await library.pushToGarmin(template) } } label: {
                    Label("Push to Garmin Connect", systemImage: "arrow.up.circle")
                }
                .disabled(library.pushDisabledReason(for: template) != nil)
                .accessibilityIdentifier("workout-editor-push")
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete workout", systemImage: "trash") }
                    .accessibilityIdentifier("workout-editor-delete")
                    .confirmationDialog("Delete \(template.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            Task { _ = await library.delete(template); dismiss() }
                        }
                    } message: {
                        Text("It is removed from JournalInsight. A copy on Garmin Connect stays there.")
                    }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if onSendToWatch != nil, let why = model.watchDisabledReason { Text(why) }
                if let why = library?.pushDisabledReason(for: template) { Text(why) }
            }
        }
    }

    @ViewBuilder private func stepDetail(_ id: UUID) -> some View {
        switch model.step(id) {
        case .cardio?:
            CardioStepForm(step: Binding(
                get: { model.step(id)?.cardio ?? WorkoutEditorViewModel.newCardioStep() },
                set: { model.update(id, to: .cardio($0)) }))
        case .strength?:
            StrengthStepForm(step: Binding(
                get: { model.step(id)?.strength ?? WorkoutEditorViewModel.newStrengthStep(nil) },
                set: { model.update(id, to: .strength($0)) }),
                options: model.exerciseOptions)
        case nil:
            Text("This step was removed.").foregroundStyle(theme.color(.muted))
        }
    }
}

/// One step line in the editor list.
struct WorkoutStepRow: View {
    let step: SegmentStep
    private let theme = JITheme.native

    var body: some View {
        switch step {
        case .cardio(let c):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WorkoutFormat.purpose(c.purpose).uppercased()).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    HStack(spacing: 6) {
                        Text(WorkoutFormat.end(c.end)).jiNumeral(.statValue)
                        if let t = WorkoutFormat.target(c.target) { Text("· \(t)").jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
                    }
                    if let d = c.description, !d.isEmpty { Text(d).jiFont(.footnote).foregroundStyle(theme.color(.muted)).lineLimit(2) }
                }
                Spacer(minLength: 0)
                if c.repeat > 1 {
                    Text("×\(c.repeat)").jiFont(.footnote, weight: .semibold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.color(.control)))
                }
            }
            .accessibilityElement(children: .combine)
        case .strength(let s):
            VStack(alignment: .leading, spacing: 2) {
                Text(s.exerciseKey.isEmpty ? "Pick an exercise" : s.exerciseKey).foregroundStyle(theme.color(.text))
                Text(WorkoutFormat.strength(s)).jiFont(.footnote).foregroundStyle(theme.color(.muted))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Detail form of one cardio step: purpose, end (time / distance / lap), target (none / bpm
/// range / zone), repeat, note.
struct CardioStepForm: View {
    @Binding var step: CardioStep

    private enum EndKind: String, CaseIterable, Identifiable { case time = "Time", distance = "Distance", lap = "Lap button"; var id: String { rawValue } }
    private enum TargetKind: String, CaseIterable, Identifiable { case none = "None", range = "Heart-rate range", zone = "Zone"; var id: String { rawValue } }

    var body: some View {
        Form {
            Section {
                Picker("Step", selection: $step.purpose) {
                    ForEach(WorkoutStepPurpose.allCases, id: \.self) { Text(WorkoutFormat.purpose($0)).tag($0) }
                }
                if step.purpose == .work || step.purpose == .recovery {
                    Stepper("Repeat ×\(step.repeat)", value: $step.repeat, in: 1...20)
                        .accessibilityIdentifier("step-repeat")
                }
            }
            Section("Ends after") {
                Picker("Ends", selection: endKind) { ForEach(EndKind.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                switch step.end {
                case .time(let s):
                    Stepper("Minutes \(s / 60)", value: minutes, in: 0...300)
                    Stepper("Seconds \(s % 60)", value: seconds, in: 0...55, step: 5)
                case .distance(let m):
                    Stepper(WorkoutFormat.distance(meters: m), value: meters, in: 100...50_000, step: 100)
                case .lap:
                    Text("The step runs until you press the lap button.").foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Target", selection: targetKind) { ForEach(TargetKind.allCases) { Text($0.rawValue).tag($0) } }
                switch step.target {
                case .hrRange(let lo, let hi):
                    Stepper("From \(lo) bpm", value: rangeLo, in: 40...(max(41, hi) - 1))
                    Stepper("To \(hi) bpm", value: rangeHi, in: (lo + 1)...WorkoutEditorViewModel.hubHrCeiling)
                case .hrZone:
                    Picker("Zone", selection: zone) { ForEach(1...5, id: \.self) { Text("Zone \($0)").tag($0) } }
                        .pickerStyle(.segmented)
                    Text("Turned into bpm from your own zones when you send it to the Watch.").jiFont(.footnote).foregroundStyle(.secondary)
                case .none:
                    Text("No heart-rate alert on this step.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Heart rate")
            } footer: {
                Text("Alerts stop at \(WorkoutEditorViewModel.hubHrCeiling) bpm.")
            }
            Section("Note") {
                TextField("Optional", text: note, axis: .vertical).lineLimit(1...4)
            }
        }
        .navigationTitle(WorkoutFormat.purpose(step.purpose))
    }

    private var endKind: Binding<EndKind> {
        Binding(get: {
            switch step.end { case .time: .time; case .distance: .distance; case .lap: .lap }
        }, set: { kind in
            switch kind {
            case .time: if case .time = step.end {} else { step.end = .time(seconds: 600) }
            case .distance: if case .distance = step.end {} else { step.end = .distance(meters: 1000) }
            case .lap: step.end = .lap
            }
        })
    }

    private var minutes: Binding<Int> {
        Binding(get: { if case .time(let s) = step.end { s / 60 } else { 0 } },
                set: { m in if case .time(let s) = step.end { step.end = .time(seconds: m * 60 + s % 60) } })
    }
    private var seconds: Binding<Int> {
        Binding(get: { if case .time(let s) = step.end { s % 60 } else { 0 } },
                set: { sec in if case .time(let s) = step.end { step.end = .time(seconds: (s / 60) * 60 + sec) } })
    }
    private var meters: Binding<Double> {
        Binding(get: { if case .distance(let m) = step.end { m } else { 1000 } }, set: { step.end = .distance(meters: $0) })
    }

    private var targetKind: Binding<TargetKind> {
        Binding(get: {
            switch step.target { case .none: .none; case .hrRange: .range; case .hrZone: .zone }
        }, set: { kind in
            switch kind {
            case .none: step.target = .none
            case .range: if case .hrRange = step.target {} else { step.target = .hrRange(lo: 120, hi: 140) }
            case .zone: if case .hrZone = step.target {} else { step.target = .hrZone(2) }
            }
        })
    }
    private var rangeLo: Binding<Int> {
        Binding(get: { if case .hrRange(let lo, _) = step.target { lo } else { 120 } },
                set: { lo in if case .hrRange(_, let hi) = step.target { step.target = .hrRange(lo: lo, hi: hi) } })
    }
    private var rangeHi: Binding<Int> {
        Binding(get: { if case .hrRange(_, let hi) = step.target { hi } else { 140 } },
                set: { hi in if case .hrRange(let lo, _) = step.target { step.target = .hrRange(lo: lo, hi: hi) } })
    }
    private var zone: Binding<Int> {
        Binding(get: { if case .hrZone(let z) = step.target { z } else { 2 } }, set: { step.target = .hrZone($0) })
    }
    private var note: Binding<String> {
        Binding(get: { step.description ?? "" }, set: { step.description = $0.isEmpty ? nil : $0 })
    }
}

/// Detail form of one strength step: exercise (our known list), sets, reps | time, kg, rest.
struct StrengthStepForm: View {
    @Binding var step: StrengthStep
    let options: [ExerciseOption]

    var body: some View {
        Form {
            Section {
                Picker("Exercise", selection: exercise) {
                    if !options.contains(where: { $0.key == step.exerciseKey }) {
                        Text(step.exerciseKey.isEmpty ? "Pick one" : step.exerciseKey).tag(step.exerciseKey)
                    }
                    ForEach(options) { Text($0.key).tag($0.key) }
                }
                .accessibilityIdentifier("strength-exercise")
                Stepper("Sets \(step.sets)", value: $step.sets, in: 1...10)
            }
            Section("Each set") {
                Picker("Measured by", selection: byTime) {
                    Text("Reps").tag(false)
                    Text("Time").tag(true)
                }
                .pickerStyle(.segmented)
                if let reps = step.reps {
                    Stepper("\(reps) reps", value: Binding(get: { reps }, set: { step.reps = $0 }), in: 1...100)
                } else if let s = step.seconds {
                    Stepper(WorkoutFormat.clock(seconds: s), value: Binding(get: { s }, set: { step.seconds = $0 }), in: 5...600, step: 5)
                }
            }
            Section {
                TextField("Weight (kg)", value: $step.weightKg, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityIdentifier("strength-weight")
                Stepper("Rest \(WorkoutFormat.clock(seconds: step.restSeconds ?? 0))",
                        value: Binding(get: { step.restSeconds ?? 0 }, set: { step.restSeconds = $0 == 0 ? nil : $0 }),
                        in: 0...600, step: 15)
            } footer: {
                Text("Leave the weight empty for bodyweight.")
            }
        }
        .navigationTitle(step.exerciseKey.isEmpty ? "Exercise" : step.exerciseKey)
    }

    private var exercise: Binding<String> {
        Binding(get: { step.exerciseKey }, set: { key in
            guard let o = options.first(where: { $0.key == key }) else { return }
            step.exerciseKey = o.key; step.garminCategory = o.garminCategory; step.garminExercise = o.garminExercise
        })
    }

    private var byTime: Binding<Bool> {
        Binding(get: { step.seconds != nil }, set: { time in
            if time { step.seconds = step.seconds ?? 45; step.reps = nil } else { step.reps = step.reps ?? 10; step.seconds = nil }
        })
    }
}
