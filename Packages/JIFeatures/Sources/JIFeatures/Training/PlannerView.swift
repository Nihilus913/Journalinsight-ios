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

/// Sessions the hub can take a weekday for (a real plan_session id — B-52's rule).
public func assignableSessions(planSessions: [PlanSessionOut], exercises: [Exercise]) -> [TrainingSessionRef] {
    weekSpine(planSessions: planSessions, exercises: exercises).compactMap { e in
        e.id.map { TrainingSessionRef(id: $0, name: e.name, weekday: e.weekday) }
    }
}

/// W-PLANNER PL-4 — the Planner (was `TrainingWeekView` "Your week"): ONE screen for the week and
/// every workout, assigned or not (Toby 2026-10-04: "the week workout view should be in the
/// strength planner, same as all the workouts assigned or not").
///   • THIS WEEK — today's seven day rows, unchanged: a tap opens that day's sheet (Change / Add /
///     Take off), and each row is a drop target (PL-7).
///   • ALL WORKOUTS — `TrainingViewModel.plannerWorkouts` (plan sessions ∪ library templates) as
///     chevron rows, filtered All / Strength / Run / Not on a day; + new, ⋯ Import. A strength row
///     opens its detail (lifts, next weights, Log sets, Send to Watch); a template row the editor.
/// Every write is the day sheet's (`TrainingViewModel.changeDay` → Outbox first, B-52).
public struct PlannerView: View {
    @Environment(\.dynamicTypeSize) private var typeSize   // W-FIX11 H1-17
    @Bindable private var model: TrainingViewModel
    @State private var dayPreview: TrainingDayRef?
    @State private var filter: PlannerFilter = .all
    @State private var editing: PlannerEditorTarget?
    @State private var showingImport = false
    @State private var strengthDetail: PlannerStrengthRef?
    @State private var pendingDelete: WorkoutTemplate?
    @State private var notice: (text: String, isError: Bool)?
    @State private var dropTarget: Int?
    @Environment(\.gateSettings) private var gateSettings
    #if canImport(WorkoutKit)
    @Environment(\.sendToWatchModel) private var sendToWatch
    @State private var showSendToWatch = false
    #endif
    /// B-33: a screen root reads the theme it installs (see `TrainingView`).
    private let theme = JITheme.native

    /// The editor sheet's subject: a new workout, or one library row.
    struct PlannerEditorTarget: Identifiable {
        let template: WorkoutTemplate?
        var id: String { template.map { "t\($0.templateId)" } ?? "new" }
    }

    public init(model: TrainingViewModel) { self.model = model }

    private var summary: TrainingWeekSummary { model.weekSummary }
    private var templates: [WorkoutTemplate] { model.library?.templates ?? [] }
    private func template(for row: PlannerWorkout) -> WorkoutTemplate? {
        row.templateId.flatMap { id in templates.first { $0.templateId == id } }
    }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text(plannerStatement)
                    .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.bottom, JISpacing.s3)
                    .accessibilityIdentifier("planner-statement")
                Surface(level: 1, padding: JISpacing.cardPadding, tint: summary.matchesPlan ? theme.color(.go) : nil) { summaryCard }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("training-week-summary")
                JISectionHeader("This week")
                weekCard
                Text("Tap a day to change it. Drag a workout onto a day to put it there; drag between days to move it.")
                    .jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s3)
                if let notice {
                    Text(notice.text).jiFont(.footnote).foregroundStyle(theme.color(notice.isError ? .danger : .muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s2)
                        .accessibilityIdentifier("planner-notice")
                }
                allWorkoutsHeader
                allWorkoutsCard
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiGlassBackButton()
        .jiTheme(.native)
        .navigationTitle("Planner")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("planner")
        .toolbar {
            if model.library != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = PlannerEditorTarget(template: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New workout")
                        .accessibilityIdentifier("workouts-new")
                }
            }
        }
        .onAppear { model.screenAppeared() }
        .refreshable { await model.refresh() }
        #if DEBUG
        // `-workout-library-open new|import|t<id>`: the editor / Import sheet once the list is up.
        .task {
            guard let route = workoutLibraryLaunchRoute(CommandLine.arguments) else { return }
            await model.library?.load()
            switch route {
            case .newWorkout: editing = PlannerEditorTarget(template: nil)
            case .importSheet: showingImport = true
            case .edit(let id): if let t = templates.first(where: { $0.templateId == id }) { editing = PlannerEditorTarget(template: t) }
            }
        }
        #endif
        .sheet(item: $dayPreview) { ref in TrainingDaySheet(model: model, weekday: ref.weekday) }
        .sheet(item: $editing) { target in
            if let library = model.library {
                WorkoutEditorSheet(
                    model: WorkoutEditorViewModel(template: target.template, exerciseOptions: library.exerciseOptions) { draft in
                        await library.save(draft, editing: target.template)
                    },
                    library: library,
                    onSendToWatch: templateSendToWatch)
            }
        }
        .sheet(isPresented: $showingImport) { if let library = model.library { ImportFromGarminSheet(model: library) } }
        #if canImport(WorkoutKit)
        .sheet(isPresented: $showSendToWatch) { if let sendToWatch { SendToWatchSheet(model: sendToWatch) } }
        #endif
        .navigationDestination(item: $strengthDetail) { row in PlannerStrengthDetail(model: model, ref: row) }
    }

    // MARK: summary + week

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

    private var weekCard: some View {
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
    }

    private func rowLabel(_ day: TrainingWeekDay, entries: [TrainingDayPreview.Entry], pending: Bool) -> some View {
        // W-FIX11 H1-17: at AX sizes the weekday sits above the title.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: JISpacing.s3))
        return layout {
            Text(trainingWeekdayShortNames[day.weekday]).jiFont(.body, weight: day.isToday ? .bold : .regular)
                .foregroundStyle(theme.color(day.isToday ? .text : .muted)).frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if entries.isEmpty {
                    Text("Rest").jiFont(.body).foregroundStyle(theme.color(.muted))
                } else {
                    ForEach(entries) { entry in entryLine(entry, weekday: day.weekday) }
                }
                if day.kind == .interval {
                    Text(trainingWeekIntervalCaption(hrCapBpm: gateSettings.hrCapBpm)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                if pending { Text("Waiting to sync").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: JISpacing.s2)
                Text(day.kind.rawValue).jiFont(.caption, weight: .bold).foregroundStyle(theme.color(.muted))
                    .accessibilityHidden(true)
            }
        }
    }

    /// One workout on a day — its own line, draggable to another day (PL-7: a move).
    @ViewBuilder private func entryLine(_ entry: TrainingDayPreview.Entry, weekday: Int) -> some View {
        let line = Text(entry.title).jiFont(.body).foregroundStyle(theme.color(.text))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("planner-day-\(weekday)-entry-\(entry.id)")
        if entry.choice != nil, let item = PlannerDragItem(payload: PlannerDragItem(ref: entry.id, fromWeekday: weekday).payload) {
            line.draggable(item.payload) { dragPreview(entry.title) }
        } else {
            line
        }
    }

    private func dragPreview(_ title: String) -> some View {
        Text(title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
            .padding(.horizontal, JISpacing.s3).padding(.vertical, JISpacing.s2)
            .background(Capsule().fill(theme.color(.info).opacity(0.25)))
    }

    /// PL-7: a Planner row dropped on a day — assign (from ALL WORKOUTS) or move (from a day).
    private func drop(_ payloads: [String], on weekday: Int) -> Bool {
        guard let payload = payloads.first, PlannerDragItem(payload: payload) != nil else { return false }
        Task {
            let result = await model.drop(payload, onDay: weekday)
            notice = trainingDayPickNotice(result)
        }
        return true
    }

    private func dayRow(_ day: TrainingWeekDay) -> some View {
        let entries = model.dayPreview(weekday: day.weekday).entries
        let pending = entries.contains { model.isPending($0) }
        let label = trainingWeekDayAccessibilityLabel(day) + (pending ? ", waiting to sync" : "")
        return Button { dayPreview = TrainingDayRef(weekday: day.weekday) } label: {
            JIChevronRow { rowLabel(day, entries: entries, pending: pending) }
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.color(.info).opacity(dropTarget == day.weekday ? 0.18 : 0)))
        .dropDestination(for: String.self) { items, _ in drop(items, on: day.weekday) } isTargeted: { over in
            if over { dropTarget = day.weekday } else if dropTarget == day.weekday { dropTarget = nil }
        }
        .accessibilityElement(children: .combine).accessibilityLabel(label)
        .accessibilityHint("Shows \(planWeekdayNames[day.weekday])'s session")
        .accessibilityIdentifier("training-week-row-\(day.weekday)")
    }

    // MARK: all workouts

    private var allWorkoutsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            JISectionHeader("All workouts")
            if let library = model.library {
                Menu {
                    Button { editing = PlannerEditorTarget(template: nil) } label: { Label("New workout", systemImage: "plus") }
                    Button { showingImport = true } label: {
                        Label(library.garminDisabledReason ?? "Import from Garmin Connect", systemImage: "square.and.arrow.down")
                    }
                    .disabled(library.garminDisabledReason != nil)
                    .accessibilityIdentifier("workouts-import")
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(theme.color(.info))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("planner-more")
            }
        }
    }

    private var allWorkoutsCard: some View {
        let all = model.plannerWorkouts
        let rows = plannerFiltered(all, filter, templates: templates)
        return VStack(alignment: .leading, spacing: JISpacing.s3) {
            Picker("Show", selection: $filter) {
                ForEach(PlannerFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("workouts-filter")
            if let library = model.library, !library.hubReachable {
                Label(library.fetchedAt.map { "Offline — showing the library from \(jiShortTime($0))." } ?? "Offline.", systemImage: "wifi.slash")
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("workouts-offline")
            }
            if let n = model.library?.notice {
                Text(n.text).jiFont(.footnote).foregroundStyle(theme.color(n.isError ? .danger : .muted))
                    .accessibilityIdentifier("workouts-notice")
            }
            Surface(level: 1, padding: 0) {
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text(plannerEmptyText(filter, hasAny: !all.isEmpty)).jiFont(.body).foregroundStyle(theme.color(.muted))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, JISpacing.s3)
                            .accessibilityIdentifier("workouts-empty")
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        if i > 0 { JIRowDivider().padding(.leading, 0) }
                        workoutRow(row).padding(.vertical, JISpacing.s3)
                    }
                }
                .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
            }
            .accessibilityIdentifier("workouts-list")
        }
    }

    private func workoutRow(_ row: PlannerWorkout) -> some View {
        let t = template(for: row)
        let pending = row.templateId.map { $0 < 0 || (model.library?.pendingTemplateIds.contains($0) ?? false) } ?? false
        return Button { open(row, template: t) } label: {
            JIChevronRow {
                HStack(spacing: JISpacing.s3) {
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: plannerRowSymbol(row, template: t))
                            .font(.title3).foregroundStyle(theme.color(.muted)).frame(width: 28).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name).jiFont(.body).foregroundStyle(theme.color(.text))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(plannerRowSubtitle(row, template: t)
                             + (row.onGarmin || t?.garmin != nil ? " · " + WorkoutFormat.garminLabel(t?.garminState ?? .current) : ""))
                            .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                        if pending { Text("Waiting to sync").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.editable ? "Opens the editor" : "Shows the lifts")
        .accessibilityIdentifier(row.templateId.map { "workouts-row-\($0)" } ?? "planner-row-\(row.ref)")
        .modifier(PlannerDraggable(payload: PlannerDragItem(payload: PlannerDragItem(ref: row.ref).payload)?.payload) { dragPreview(row.name) })
        .contextMenu { rowMenu(row, template: t) }
        // B40-V8: the confirmation hangs off the row being deleted, so its popover points at it.
        .confirmationDialog("Delete \(t?.name ?? row.name)?", isPresented: deleteBinding(for: t), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let t, let library = model.library else { return }
                pendingDelete = nil
                Task { _ = await library.delete(t) }
            }
        } message: {
            Text("It is removed from JournalInsight. A copy on Garmin Connect stays there.")
        }
    }

    private func deleteBinding(for t: WorkoutTemplate?) -> Binding<Bool> {
        Binding(get: { t != nil && pendingDelete?.templateId == t?.templateId }, set: { if !$0 { pendingDelete = nil } })
    }

    @ViewBuilder private func rowMenu(_ row: PlannerWorkout, template t: WorkoutTemplate?) -> some View {
        if let t, let library = model.library {
            if let send = templateSendToWatch, t.hasCardio {
                Button { send(t) } label: { Label("Send to Watch", systemImage: "applewatch") }
            }
            Button { Task { await library.pushToGarmin(t) } } label: {
                Label(library.pushDisabledReason(for: t) ?? "Push to Garmin Connect", systemImage: "arrow.up.circle")
            }
            .disabled(library.pushDisabledReason(for: t) != nil)
            Button(role: .destructive) { pendingDelete = t } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func open(_ row: PlannerWorkout, template t: WorkoutTemplate?) {
        if let t { editing = PlannerEditorTarget(template: t); return }
        if row.kind == .planSession { strengthDetail = PlannerStrengthRef(row) }
    }

    /// B40-V7: a library workout's "Send to Watch" — the B-37 sheet, that workout picked.
    private var templateSendToWatch: ((WorkoutTemplate) -> Void)? {
        #if canImport(WorkoutKit)
        guard let sendToWatch else { return nil }
        return { template in sendToWatch.pickOnly(template.templateId); showSendToWatch = true }
        #else
        nil
        #endif
    }
}

/// PL-7: a Planner row is draggable only when it names a real plan session / template.
private struct PlannerDraggable<Preview: View>: ViewModifier {
    let payload: String?
    @ViewBuilder let preview: () -> Preview
    func body(content: Content) -> some View {
        if let payload { content.draggable(payload) { preview() } } else { content }
    }
}
