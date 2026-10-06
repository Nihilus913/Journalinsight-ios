import SwiftUI
import JICore
import JICompute
import JIDesign
import JIPersistence

/// W-B38-A A-10 — the iPhone strength logger ("Log sets" from Training's Start session). Native
/// controls (TextField / Stepper / Toggle / Menu) inside the W-GUI primitives (ScreenScroll,
/// Surface, JISectionHeader). Every number on screen is a real value or a dash — never a seeded 0.
public struct StrengthLogView: View {
    @Bindable private var model: StrengthLogViewModel
    private let history: StrengthHistoryViewModel?
    @State private var editing: StrengthSetLog?
    @State private var showPlates = false
    @State private var showHistory = false
    @State private var records: StrengthRecordsViewModel?
    /// W-B38-B B-10: the exercise library, whose pick adds an exercise to this session.
    @State private var showLibrary = false
    private let theme = JITheme.native

    public init(model: StrengthLogViewModel, history: StrengthHistoryViewModel? = nil) {
        self.model = model; self.history = history
    }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                if model.timer.phase != .idle { StrengthRestTimer(model: model) }
                if model.cards.isEmpty {
                    Surface { Text("No exercises in this training yet — add them to the plan first.")
                        .jiFont(.body).foregroundStyle(theme.color(.muted)) }
                        .accessibilityIdentifier("strength-log-empty")
                }
                ForEach(model.cards) { card in
                    StrengthExerciseCard(model: model, card: card, onEdit: { editing = $0 })
                }
                completeSection
                if let note = model.syncNote {
                    Text(note).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("strength-log-sync-note")
                }
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiTheme(.native)
        .navigationTitle(model.sessionName ?? "Log sets")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showLibrary = true } label: { Label("Add exercise", systemImage: "plus") }
                    .accessibilityIdentifier("strength-log-add-exercise")
                Button { showPlates = true } label: { Label("Plates", systemImage: "circle.grid.2x1") }
                    .accessibilityIdentifier("strength-log-plates")
                if history != nil {
                    Button { showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                        .accessibilityIdentifier("strength-log-history")
                    Button { records = history?.makeRecords() } label: { Label("Records", systemImage: "trophy") }
                        .accessibilityIdentifier("strength-log-records")
                }
            }
        }
        .task { await model.load() }
        .sheet(item: $editing) { set in
            StrengthSetEditSheet(set: set) { kg, reps, duration, rpe in
                model.editSet(set, weightKg: kg, reps: reps, durationS: duration, rpe: rpe)
            } onDelete: { model.deleteSet(set) }
        }
        .sheet(isPresented: $showPlates) { StrengthPlatesSheet(inventory: model.plates) { model.savePlates($0) } }
        .navigationDestination(isPresented: $showLibrary) {
            ExerciseLibraryView(model: ExerciseLibraryViewModel(options: WorkoutExerciseCatalogue.known) { model.addExercise($0) })
        }
        .navigationDestination(isPresented: $showHistory) {
            if let history { StrengthHistoryView(model: history) }
        }
        .navigationDestination(item: $records) { StrengthRecordsView(model: $0) }
    }

    private var completeSection: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: JISpacing.s3) {
                Toggle(isOn: $model.autoSuggest) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-suggest next weight").jiFont(.body)
                        Text(model.autoSuggest
                             ? "When every set hits its reps, Complete moves the target up one step."
                             : "Complete keeps your targets as they are.")
                            .jiFont(.caption).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(theme.color(.info))
                .accessibilityIdentifier("strength-log-autosuggest")
                if let advance = model.completedAdvance {
                    Text(completedText(advance)).jiFont(.body).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("strength-log-completed")
                } else {
                    Button { Task { await model.complete() } } label: {
                        Text("Complete session").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(theme.color(.info)).controlSize(.large)
                    .disabled(!model.canComplete)
                    .accessibilityIdentifier("strength-log-complete")
                }
            }
        }
    }

    private func completedText(_ advance: [StrengthAdvance]) -> String {
        guard !advance.isEmpty else { return "Session complete. Targets unchanged." }
        let names = advance.compactMap { a in
            model.cards.first { $0.lift.exerciseId == a.exerciseId }.map { "\($0.lift.exerciseKey) → \(StrengthFormat.kg(a.currentWeightKg))" }
        }
        return "Session complete. Next time: " + names.joined(separator: ", ") + "."
    }
}

nonisolated enum StrengthFormat {
    static func kg(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        return v == v.rounded() ? String(format: "%.0f kg", v) : (abs(v * 10 - (v * 10).rounded()) < 0.001 ? String(format: "%.1f kg", v) : String(format: "%.2f kg", v))
    }

    static func setLine(_ s: StrengthSetLog) -> String {
        var parts: [String] = []
        if s.kind == .timed { parts.append(s.durationS.map { "\($0) s" } ?? "—") }
        else {
            if let w = s.weightKg, w > 0 { parts.append("\(kg(w)) × \(s.reps.map(String.init) ?? "—")") }
            else { parts.append("\(s.reps.map(String.init) ?? "—") reps") }
        }
        if let rpe = s.rpe { parts.append("RPE \(rpe == rpe.rounded() ? String(Int(rpe)) : String(format: "%.1f", rpe))") }
        return parts.joined(separator: " · ")
    }

    static func plates(_ plates: [Double]?, load: StrengthLoad = .barbell) -> String {
        guard let plates else { return "Not reachable with your plates" }
        if plates.isEmpty { return load == .dumbbell ? "Empty handle" : "Empty bar" }
        return (load == .dumbbell ? "Per dumbbell side: " : "Per side: ") + plates.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }.joined(separator: " + ")
    }

    /// W-FIX-P3 RG-67: the plates line, or nil = no line. Hidden for a bodyweight lift and for a
    /// dumbbell weight the plates cannot build (a fixed dumbbell, e.g. 12 kg per hand).
    static func platesHint(_ plates: [Double]?, load: StrengthLoad, bodyweight: Bool) -> String? {
        if bodyweight { return nil }
        if plates == nil, load == .dumbbell { return nil }
        return Self.plates(plates, load: load)
    }
}

/// One exercise: target + muscles, the sets logged so far, and the entry row for the next set.
struct StrengthExerciseCard: View {
    @Bindable var model: StrengthLogViewModel
    let card: StrengthLogViewModel.Card
    let onEdit: (StrengthSetLog) -> Void
    @State private var weightText = ""
    @State private var reps = 0
    @State private var seconds = 0
    @State private var rpe: Double?
    @State private var primed = false
    @State private var showCalculator = false   // W-B38-B B-9
    private let theme = JITheme.native

    var body: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: JISpacing.s3) {
                header
                if !card.sets.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(card.sets) { s in
                            Button { onEdit(s) } label: {
                                HStack {
                                    Text("Set \(s.setIndex)").jiFont(.body).foregroundStyle(theme.color(.muted))
                                    Spacer()
                                    Text(StrengthFormat.setLine(s)).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                                    Image(systemName: "pencil").foregroundStyle(theme.color(.muted)).accessibilityHidden(true)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressableScale)
                            .accessibilityLabel("Set \(s.setIndex), \(StrengthFormat.setLine(s)). Edit")
                            .accessibilityIdentifier("strength-set-\(card.lift.exerciseKey)-\(s.setIndex)")
                            .contextMenu {
                                Button("Edit") { onEdit(s) }
                                Button("Delete", role: .destructive) { model.deleteSet(s) }
                            }
                        }
                    }
                }
                entry
            }
        }
        .onAppear(perform: prime)
        .onChange(of: card.defaults) { _, _ in prime(force: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.lift.exerciseKey).jiFont(.cardTitle).foregroundStyle(theme.color(.text))
            Text(targetLine).jiFont(.caption).foregroundStyle(theme.color(.muted))
            if let muscles = card.muscles {
                Text(muscles.joined(separator: " · ")).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .accessibilityLabel("Targets \(muscles.joined(separator: ", "))")
            }
            if let last = card.lastTime.last {
                Text("Last time: \(StrengthFormat.setLine(last))").jiFont(.caption).foregroundStyle(theme.color(.muted))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var targetLine: String {
        let sets = card.lift.sets.map { "\($0) ×" } ?? ""
        let reps = card.lift.repsTarget ?? "—"
        let kg = card.lift.nextKg ?? card.lift.currentKg
        let target = [sets, reps].filter { !$0.isEmpty }.joined(separator: " ")
        return kg.map { "Target \(target) · \(StrengthFormat.kg($0))" } ?? "Target \(target)"
    }

    @ViewBuilder private var entry: some View {
        let timed = card.lift.isTimed
        VStack(alignment: .leading, spacing: JISpacing.s2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: JISpacing.s3) { fields(timed: timed) }
                VStack(alignment: .leading, spacing: JISpacing.s2) { fields(timed: timed) }
            }
            // W-FIX-P3 RG-67: no plates line for a bodyweight lift or a fixed-dumbbell weight.
            if !timed, let hint = StrengthFormat.platesHint(model.plates(for: parsedKg, exerciseKey: card.lift.exerciseKey),
                                                             load: StrengthLoad.of(card.lift.exerciseKey), bodyweight: card.lift.isBodyweight || StrengthLoad.isFixedWeight(card.lift.exerciseKey)) {
                // W-B38-B B-9: the per-side line opens the plate calculator sheet for this weight.
                Button { if parsedKg != nil { showCalculator = true } } label: {
                    Label(hint, systemImage: "circle.grid.2x1")
                        .jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                .buttonStyle(.plain)
                .disabled(parsedKg == nil)
                .accessibilityHint("Shows the plates for each side")
                .accessibilityIdentifier("strength-plates-\(card.lift.exerciseKey)")
                .sheet(isPresented: $showCalculator) {
                    if let kg = parsedKg { PlateCalculatorSheet(model: PlateCalculatorViewModel(totalKg: kg, inventory: model.plates, load: StrengthLoad.of(card.lift.exerciseKey))) }
                }
            }
            HStack {
                Menu {
                    Button("No RPE") { rpe = nil }
                    ForEach([6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0], id: \.self) { v in
                        Button("RPE \(v == v.rounded() ? String(Int(v)) : String(v))") { rpe = v }
                    }
                } label: {
                    Label(rpe.map { "RPE \($0 == $0.rounded() ? String(Int($0)) : String($0))" } ?? "RPE", systemImage: "gauge.with.dots.needle.33percent")
                }
                .accessibilityIdentifier("strength-rpe-\(card.lift.exerciseKey)")
                Spacer()
                Button {
                    model.logSet(exerciseKey: card.lift.exerciseKey, weightKg: parsedKg, reps: timed ? nil : reps,
                                 durationS: timed ? seconds : nil, rpe: rpe)
                } label: { Text("Log set \(card.nextSetIndex)") }
                .buttonStyle(.borderedProminent).tint(theme.color(.info))
                .disabled(!model.canLogSet)
                .accessibilityIdentifier("strength-log-set-\(card.lift.exerciseKey)")
            }
            if let error = model.error {
                Text(error).jiFont(.caption).foregroundStyle(theme.color(.danger))
            }
        }
    }

    @ViewBuilder private func fields(timed: Bool) -> some View {
        if timed {
            Stepper(value: $seconds, in: 0...600, step: 5) {
                Text(seconds > 0 ? "\(seconds) s" : "— s").jiFont(.body, weight: .semibold).monospacedDigit()
            }
            .accessibilityValue(seconds > 0 ? "\(seconds) seconds" : "not set")
        } else {
            HStack(spacing: 4) {
                TextField("kg", text: $weightText)
                    .strengthDecimalField()
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 72, maxWidth: 110)
                    .accessibilityLabel("Weight in kilograms")
                    .accessibilityIdentifier("strength-weight-\(card.lift.exerciseKey)")
                Text("kg").jiFont(.body).foregroundStyle(theme.color(.muted))
            }
            Stepper(value: $reps, in: 0...100) {
                Text(reps > 0 ? "\(reps) reps" : "— reps").jiFont(.body, weight: .semibold).monospacedDigit()
            }
            .accessibilityValue(reps > 0 ? "\(reps) reps" : "not set")
            .accessibilityIdentifier("strength-reps-\(card.lift.exerciseKey)")
        }
    }

    private var parsedKg: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
    }

    private func prime() { prime(force: false) }

    private func prime(force: Bool) {
        guard force || !primed else { return }
        primed = true
        let d = card.defaults
        weightText = d.weightKg.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? ""
        reps = d.reps ?? 0
        seconds = card.lift.timedSeconds ?? card.sets.last?.durationS ?? 0
    }
}

/// The rest / timed-set countdown (gap #29/#31).
struct StrengthRestTimer: View {
    @Bindable var model: StrengthLogViewModel
    private let theme = JITheme.native

    var body: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = model.timer.remainingSeconds(at: context.date) ?? 0
                let done = model.timer.isFinished(at: context.date)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.timer.phase == .timedSet ? "Hold" : "Rest").jiFont(.caption).foregroundStyle(theme.color(.muted))
                        Text(done ? "Go" : DurationFormat.clock(seconds: left)).jiFont(.numeralMedium).monospacedDigit()
                            .foregroundStyle(theme.color(.text))
                    }
                    Spacer()
                    Button("+30 s") { model.timer = model.timer.adding(seconds: 30) }.buttonStyle(.bordered)
                    Button(done ? "Dismiss" : "Skip") { model.timer = model.timer.stopped() }.buttonStyle(.bordered)
                        .accessibilityIdentifier("strength-rest-skip")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(done ? "Rest over" : "Rest, \(left) seconds left")
            }
        }
        .accessibilityIdentifier("strength-rest-timer")
    }
}

/// Edit / delete one logged set (gap #31).
struct StrengthSetEditSheet: View {
    let set: StrengthSetLog
    let onSave: (Double?, Int?, Int?, Double?) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var reps = 0
    @State private var seconds = 0
    @State private var rpeText = ""

    var body: some View {
        NavigationStack {
            Form {
                if set.kind == .timed {
                    Stepper("\(seconds) s", value: $seconds, in: 5...600, step: 5)
                } else {
                    TextField("Weight (kg)", text: $weightText).strengthDecimalField()
                    Stepper("\(reps) reps", value: $reps, in: 1...100)
                }
                TextField("RPE (optional, 0–10)", text: $rpeText).strengthDecimalField()
                Section {
                    Button("Delete set", role: .destructive) { onDelete(); dismiss() }
                        .accessibilityIdentifier("strength-edit-delete")
                }
            }
            .navigationTitle("Set \(set.setIndex) · \(set.exerciseKey)")
            .strengthInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let kg = Double(weightText.replacingOccurrences(of: ",", with: "."))
                        let rpe = Double(rpeText.replacingOccurrences(of: ",", with: ".")).flatMap { (0...10).contains($0) ? $0 : nil }
                        onSave(kg, set.kind == .timed ? nil : reps, set.kind == .timed ? seconds : nil, rpe)
                        dismiss()
                    }
                    .accessibilityIdentifier("strength-edit-save")
                }
            }
            .onAppear {
                weightText = set.weightKg.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? ""
                reps = set.reps ?? 1
                seconds = set.durationS ?? 30
                rpeText = set.rpe.map { String($0) } ?? ""
            }
        }
    }
}

/// The editable plate inventory (decision: standard + microplates by default, editable).
struct StrengthPlatesSheet: View {
    let inventory: PlateInventory
    let onSave: (PlateInventory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var barText = ""
    @State private var pairsText = ""
    @State private var invalid = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Bar") {
                    TextField("Bar (kg)", text: $barText).strengthDecimalField()
                }
                Section {
                    TextField("Plates", text: $pairsText, axis: .vertical)
                } header: { Text("Plate pairs (kg)") } footer: {
                    Text("One number per pair you own, e.g. 20, 10, 10, 5, 2.5, 1.25. Repeat a size for more pairs.")
                }
                if invalid { Text("Enter positive numbers only.").foregroundStyle(.red) }
                Section {
                    Button("Reset to standard + microplates") {
                        barText = format(PlateInventory.default.barKg)
                        pairsText = PlateInventory.default.pairs.map(format).joined(separator: ", ")
                    }
                }
            }
            .navigationTitle("Plates")
            .strengthInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let bar = Double(barText.replacingOccurrences(of: ",", with: ".")), bar > 0,
                              let pairs = PlateInventory.parsePairs(pairsText) else { invalid = true; return }
                        onSave(PlateInventory(barKg: bar, pairs: pairs)); dismiss()
                    }
                }
            }
            .onAppear {
                barText = format(inventory.barKg)
                pairsText = inventory.pairs.map(format).joined(separator: ", ")
            }
        }
    }

    private func format(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
}

// Same iOS-only guard as `ConnectionSheet.swift` (controller ruling 2): `swift test` builds macOS.
extension View {
    @ViewBuilder func strengthDecimalField() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder func strengthInlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
