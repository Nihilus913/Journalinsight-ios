import SwiftUI
import JICore
import JIDesign

// W-B40 L3 (B-82) — Training day-first. Replaces B-45's session-first `AssignWeekdaySheet`
// ("Which day is Full upper?"): the user starts from the DAY. Tap a day → this sheet previews that
// day's session(s) → Change / Add = a picker over the plan sessions and the B-40 workout library.
// Every pick is offline-first (`TrainingViewModel.changeDay`): it shows at once, marked
// "Waiting to sync" until the hub has it.

/// The sheet's subject (Mon = 0 … Sun = 6).
public struct TrainingDayRef: Identifiable, Hashable, Sendable {
    public let weekday: Int
    public var id: Int { weekday }
    public init(weekday: Int) { self.weekday = weekday }
}

/// A plan session the week strip can point at (id = the `plan.plan_session` id `PUT` takes).
public struct TrainingSessionRef: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let weekday: Int?
    public init(id: Int, name: String, weekday: Int?) { self.id = id; self.name = name; self.weekday = weekday }
}

// MARK: - Text (pure, testable)

/// "Wednesday · 30 Sep" — the weekday alone when the date is unknown.
public nonisolated func trainingDaySheetTitle(weekday: Int, date: String) -> String {
    let name = planWeekdayNames[weekday]
    guard let d = trainingStripDate(date) else { return name }
    return name + " · " + d.formatted(Date.FormatStyle(timeZone: trainingStripCalendar.timeZone).day().month(.abbreviated))
}

/// "3 × 8 · 50 kg" — only the parts the plan holds (never a zero for a missing weight).
public nonisolated func trainingLiftLine(_ e: Exercise) -> String? {
    var parts: [String] = []
    switch (e.sets, e.repsTarget) {
    case let (s?, r?): parts.append("\(s) × \(r)")
    case let (s?, nil): parts.append("\(s) sets")
    case let (nil, r?): parts.append("\(r) reps")
    case (nil, nil): break
    }
    if let kg = e.currentWeightKg, kg > 0 { parts.append(kg.formatted(.number.precision(.fractionLength(0...1))) + " kg") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

public nonisolated func trainingDayEntrySubtitle(_ entry: TrainingDayPreview.Entry) -> String {
    switch entry {
    case .strength(_, _, let lifts):
        lifts.isEmpty ? "Strength" : "Strength · \(lifts.count) lift\(lifts.count == 1 ? "" : "s")"
    case .template(let t): WorkoutFormat.summary(t)
    case .session(_, _, let kind): "\(trainingKindTitle(kind)) · in your plan"
    case .scheduled(_, let kind): "\(trainingKindTitle(kind)) · follows the morning-call schedule"
    }
}

/// "Long run", "Intervals", "Rest", "Strength".
nonisolated func trainingKindTitle(_ kind: TrainingWeekDayKind) -> String {
    kind.word.prefix(1).uppercased() + kind.word.dropFirst()
}

/// The glyph for a plan kind (the library rows use their template's sport).
nonisolated func trainingKindSymbol(_ kind: TrainingWeekDayKind) -> String {
    switch kind {
    case .strength: "dumbbell.fill"
    case .interval, .longRun: "figure.run"
    case .rest: "bed.double.fill"
    }
}

/// "On Mon, Fri" / "Not on a day".
public nonisolated func trainingDayOptionSubtitle(_ o: TrainingDayOption) -> String {
    o.currentDays.isEmpty ? "Not on a day" : "On " + o.currentDays.map { trainingWeekdayShortNames[$0] }.joined(separator: ", ")
}

public func trainingDayPickNotice(_ r: TrainingViewModel.DayChangeResult) -> (text: String, isError: Bool)? {
    switch r {
    case .saved: nil
    case .queued: ("Saved on this phone — it syncs when the hub is reachable.", false)
    case .refused(let why): (why, true)
    }
}

nonisolated func trainingDayEntrySymbol(_ entry: TrainingDayPreview.Entry) -> String {
    switch entry {
    case .strength: "dumbbell.fill"
    case .template(let t): WorkoutFormat.sportSymbol(t.hasStrength ? .strength : (t.effectiveSegments.first?.sport ?? .running))
    case .session(_, _, let kind): trainingKindSymbol(kind)
    case .scheduled: "calendar"
    }
}

// MARK: - Sheet

public struct TrainingDaySheet: View {
    @Bindable private var model: TrainingViewModel
    private let weekday: Int
    @State private var path: [Route] = []
    @State private var notice: (text: String, isError: Bool)?
    @State private var busy = false
    @State private var pendingRemove: TrainingDayPreview.Entry?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private let theme = JITheme.native

    public enum Route: Hashable, Sendable {
        /// The picker; `replacing` = the entry id it swaps out (nil = add to the day).
        case pick(replacing: String?)
        case library
    }

    public init(model: TrainingViewModel, weekday: Int, initialRoute: Route? = nil) {
        self.model = model
        self.weekday = weekday
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    private var preview: TrainingDayPreview { model.dayPreview(weekday: weekday) }
    private var dayName: String { planWeekdayNames[weekday] }

    public var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(dayName)
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("training-day-done")
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .pick(let replacingId):
                        TrainingDayPicker(model: model, weekday: weekday,
                                          replacing: preview.entries.first { $0.id == replacingId },
                                          openLibrary: { path.append(.library) }) { result in
                            notice = trainingDayPickNotice(result)
                            if case .refused = result { return }
                            path.removeAll()
                        }
                    case .library:
                        if let library = model.library { WorkoutLibraryView(model: library) }
                    }
                }
        }
        .confirmationDialog("Take \(pendingRemove?.title ?? "") off \(dayName)?",
                            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
                            titleVisibility: .visible) {
            Button("Take off \(dayName)", role: .destructive) {
                guard let entry = pendingRemove else { return }
                pendingRemove = nil
                Task { await run(adding: nil, removing: entry) }
            }
        } message: {
            Text("It stays in your plan and library — just not on \(dayName).")
        }
        .jiTheme(.native)
        .accessibilityIdentifier("training-day-sheet")
    }

    private var content: some View {
        let p = preview
        return Form {
            Section {
                if p.isRest {
                    Text("Rest day — nothing planned.")
                        .foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("training-day-rest")
                }
            } header: {
                Text(trainingDaySheetTitle(weekday: weekday, date: p.date) + (p.isToday ? " · today" : ""))
            }
            ForEach(p.entries) { entry in entrySection(entry) }
            Section {
                NavigationLink(value: Route.pick(replacing: nil)) {
                    Label(p.isRest ? "Choose a session" : "Add a session", systemImage: "plus.circle")
                }
                .disabled(busy)
                .accessibilityIdentifier("training-day-add")
            } footer: {
                Text("Picks save on this phone first and sync to the hub when it's reachable.")
            }
            if let notice {
                Section {
                    Text(notice.text).foregroundStyle(theme.color(notice.isError ? .danger : .muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("training-day-notice")
                }
            }
        }
        .scrollContentBackground(.hidden)   // W-GUI tier B: on the ground
        .jiPageGround()
    }

    @ViewBuilder private func entrySection(_ entry: TrainingDayPreview.Entry) -> some View {
        Section {
            entryRow(entry)
            if case .strength(_, _, let lifts) = entry {
                ForEach(lifts, id: \.exerciseId) { lift in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) { liftName(lift); Spacer(minLength: JISpacing.s2); liftValue(lift) }
                        VStack(alignment: .leading, spacing: 2) { liftName(lift); liftValue(lift) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if entry.choice != nil {
                NavigationLink(value: Route.pick(replacing: entry.id)) {
                    Label("Change", systemImage: "arrow.left.arrow.right")
                }
                .disabled(busy)
                .accessibilityIdentifier("training-day-change-\(entry.id)")
                Button(role: .destructive) { pendingRemove = entry } label: {
                    Label { Text("Take off \(dayName)") } icon: {
                        Image(systemName: "minus.circle").foregroundStyle(theme.color(.danger))
                    }
                }
                .disabled(busy)
                .accessibilityIdentifier("training-day-remove-\(entry.id)")
            }
        }
    }

    private func entryRow(_ entry: TrainingDayPreview.Entry) -> some View {
        let pending = model.isPending(entry)
        return HStack(alignment: .top, spacing: JISpacing.s3) {
            // AX sizes: the glyph would outgrow its well and clip at the leading edge — the title carries it.
            if !typeSize.isAccessibilitySize {
                Image(systemName: trainingDayEntrySymbol(entry))
                    .font(.title3).foregroundStyle(theme.color(.muted))
                    .frame(width: 28).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                Text(trainingDayEntrySubtitle(entry)).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                if pending {
                    Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                        .jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("training-day-pending-\(entry.id)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("training-day-entry-\(entry.id)")
    }

    private func liftName(_ lift: Exercise) -> some View {
        Text(lift.exerciseName).jiFont(.subheadline).foregroundStyle(theme.color(.text))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func liftValue(_ lift: Exercise) -> some View {
        if let line = trainingLiftLine(lift) {
            Text(line).jiFont(.subheadline).foregroundStyle(theme.color(.muted))
        }
    }

    private func run(adding: TrainingDayChoice?, removing: TrainingDayPreview.Entry?) async {
        busy = true
        defer { busy = false }
        notice = trainingDayPickNotice(await model.changeDay(weekday: weekday, adding: adding, removing: removing))
    }
}

// MARK: - Picker

/// The change picker: the plan sessions, then the whole B-40 workout library (rendered from the
/// library's cache when the hub is unreachable). A tap writes at once (offline-first) and returns.
struct TrainingDayPicker: View {
    @Bindable var model: TrainingViewModel
    let weekday: Int
    let replacing: TrainingDayPreview.Entry?
    let openLibrary: () -> Void
    let onPicked: (TrainingViewModel.DayChangeResult) -> Void
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    private let theme = JITheme.native

    private var dayName: String { planWeekdayNames[weekday] }

    var body: some View {
        let options = model.dayOptions(weekday: weekday)
        List {
            Section {
                EmptyView()
            } header: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(replacing.map { "Replaces \($0.title) on \(dayName)." } ?? "Adds to \(dayName).")
                        .accessibilityIdentifier("training-day-picker-intent")
                    if let library = model.library, !library.hubReachable {
                        Label("Offline — your pick is saved on this phone and syncs later.", systemImage: "wifi.slash")
                            .accessibilityIdentifier("training-day-picker-offline")
                    }
                    if let error {
                        Text(error).foregroundStyle(theme.color(.danger))
                            .accessibilityIdentifier("training-day-picker-error")
                    }
                }
                .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !options.plan.isEmpty {
                Section("Your plan") { ForEach(options.plan) { optionRow($0) } }
            }
            librarySection(options.library)
        }
        .jiNativeFormChrome()
        .scrollContentBackground(.hidden)
        .jiPageGround()
        .navigationTitle(replacing == nil ? "Add to \(dayName)" : "Change \(dayName)")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("training-day-picker")
    }

    @ViewBuilder private func librarySection(_ rows: [TrainingDayOption]) -> some View {
        Section {
            if let library = model.library {
                switch library.state {
                case .idle, .loading where library.templates.isEmpty:
                    VStack(alignment: .leading, spacing: 8) { SkeletonBlock(width: 180); SkeletonBlock(width: 120, height: 12) }
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("training-day-library-loading")
                case .failed(let why) where library.templates.isEmpty:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't load the workout library").foregroundStyle(theme.color(.text))
                        Text(why).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        Button("Retry") { Task { await library.load() } }
                    }
                    .accessibilityIdentifier("training-day-library-error")
                default:
                    if rows.isEmpty {
                        Text("No workouts in the library yet.").foregroundStyle(theme.color(.muted))
                            .accessibilityIdentifier("training-day-library-empty")
                    } else {
                        ForEach(rows) { optionRow($0) }
                    }
                }
                Button(action: openLibrary) {
                    Label("Open workout library", systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("training-day-open-library")
            } else {
                Text("The workout library needs the hub connection.").foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("training-day-library-unavailable")
            }
        } header: {
            Text("Workout library")
        }
    }

    private func optionRow(_ o: TrainingDayOption) -> some View {
        Button {
            Task {
                busy = true
                let result = await model.changeDay(weekday: weekday, adding: o.choice, removing: replacing)
                busy = false
                if case .refused(let why) = result { error = why }
                onPicked(result)
            }
        } label: {
            HStack(spacing: JISpacing.s3) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: o.template.map { t in WorkoutFormat.sportSymbol(t.hasStrength ? .strength : (t.effectiveSegments.first?.sport ?? .running)) } ?? trainingKindSymbol(o.kind))
                        .font(.title3).foregroundStyle(theme.color(.muted))
                        .frame(width: 28).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(o.title).jiFont(.body).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                    Text([o.template.map(WorkoutFormat.summary), trainingDayOptionSubtitle(o)].compactMap { $0 }.joined(separator: " · "))
                        .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: JISpacing.s2)
                if o.isOnThisDay {
                    Image(systemName: "checkmark").foregroundStyle(theme.color(.info))
                        .accessibilityLabel("On \(dayName)")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableScale)
        .disabled(busy)
        .accessibilityIdentifier("training-day-option-\(o.id)")
    }
}
