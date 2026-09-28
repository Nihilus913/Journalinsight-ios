import SwiftUI
import JICore
import JIDesign

/// W-B40 L2 (B-40b-3, spec §4, mockups row 2 "Workout library") — every workout we authored:
/// sport badge, weekday chips (B-45's assignment, read-only here), Garmin state (*current* /
/// *outdated* / *not pushed*). Row: open the editor; swipe / menu: Send to Watch, Push to Garmin,
/// Delete. Toolbar: New, Import from Garmin. Offline: the cached library with a staleness line,
/// Push / Import disabled with the reason (spec §10.4).
///
/// Presented inside the host's navigation stack (the Training tab pushes it); `onSendToWatch`
/// hands a template to the B-37 Send-to-Watch sheet the host owns (nil hides the action).
public struct WorkoutLibraryView: View {
    @Bindable private var model: WorkoutLibraryViewModel
    private let onSendToWatch: ((WorkoutTemplate) -> Void)?
    @State private var editing: EditorTarget?
    @State private var showingImport = false
    @State private var pendingDelete: WorkoutTemplate?
    private let theme = JITheme.native

    /// The editor sheet's subject: a new workout, or one row.
    struct EditorTarget: Identifiable {
        let template: WorkoutTemplate?
        var id: String { template.map { "t\($0.templateId)" } ?? "new" }
    }

    public init(model: WorkoutLibraryViewModel, onSendToWatch: ((WorkoutTemplate) -> Void)? = nil) {
        self.model = model
        self.onSendToWatch = onSendToWatch
    }

    public var body: some View {
        content
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = EditorTarget(template: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New workout")
                        .accessibilityIdentifier("workouts-new")
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sheet(item: $editing) { target in
                WorkoutEditorSheet(
                    model: WorkoutEditorViewModel(template: target.template, exerciseOptions: model.exerciseOptions) { draft in
                        await model.save(draft, editing: target.template)
                    },
                    library: model,
                    onSendToWatch: onSendToWatch)
            }
            .sheet(isPresented: $showingImport) { ImportFromGarminSheet(model: model) }
            .confirmationDialog("Delete \(pendingDelete?.name ?? "workout")?", isPresented: deleteBinding, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let t = pendingDelete { Task { _ = await model.delete(t) } }
                    pendingDelete = nil
                }
            } message: {
                Text("It is removed from JournalInsight. A copy on Garmin Connect stays there.")
            }
            .jiTheme(.native)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    /// §8.5: the list without the navigation shell — what a sweep / preview renders.
    @ViewBuilder var content: some View {
        List {
            header
            templatesSection
            importSection
        }
        .jiNativeFormChrome()
        .accessibilityIdentifier("workouts-list")
    }

    @ViewBuilder private var header: some View {
        Section {
            Picker("Show", selection: $model.filter) {
                ForEach(WorkoutLibraryViewModel.SportFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("workouts-filter")
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            VStack(alignment: .leading, spacing: 6) {
                if let line = model.summaryLine {
                    Text(line).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("workouts-summary")
                }
                if !model.hubReachable {
                    Label(offlineLine, systemImage: "wifi.slash")
                        .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("workouts-offline")
                }
                if let notice = model.notice {
                    Text(notice.text).jiFont(.footnote)
                        .foregroundStyle(notice.isError ? theme.color(.danger) : theme.color(.muted))
                        .accessibilityIdentifier("workouts-notice")
                }
            }
            .textCase(nil)
        }
    }

    private var offlineLine: String {
        if let at = model.fetchedAt { return "Offline — showing the library from \(jiShortTime(at))." }
        return "Offline."
    }

    @ViewBuilder private var templatesSection: some View {
        Section {
            switch model.state {
            case .idle, .loading where model.templates.isEmpty:
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) { SkeletonBlock(width: 180); SkeletonBlock(width: 120, height: 12) }
                        .padding(.vertical, 6)
                }
                .accessibilityIdentifier("workouts-loading")
            case .failed(let why) where model.templates.isEmpty:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load the library").foregroundStyle(theme.color(.text))
                    Text(why).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    Button("Retry") { Task { await model.load() } }.accessibilityIdentifier("workouts-retry")
                }
                .accessibilityIdentifier("workouts-error")
            default:
                if model.visibleTemplates.isEmpty {
                    Text(model.templates.isEmpty ? "No workouts yet — tap + or import from Garmin Connect." : "None in this filter.")
                        .foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("workouts-empty")
                } else {
                    ForEach(model.visibleTemplates) { t in row(t) }
                }
            }
        }
    }

    private func row(_ t: WorkoutTemplate) -> some View {
        Button { editing = EditorTarget(template: t) } label: {
            WorkoutLibraryRow(template: t, pending: model.pendingTemplateIds.contains(t.templateId),
                              busy: model.busyGarminIds.contains(t.templateId))
        }
        .buttonStyle(.pressableScale)
        .accessibilityIdentifier("workouts-row-\(t.templateId)")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = t } label: { Label("Delete", systemImage: "trash") }
            if model.pushDisabledReason(for: t) == nil {
                Button { Task { await model.pushToGarmin(t) } } label: { Label("Push to Garmin", systemImage: "arrow.up.circle") }
                    .tint(theme.color(.info))
            }
        }
        .contextMenu {
            if let onSendToWatch, t.hasCardio {
                Button { onSendToWatch(t) } label: { Label("Send to Watch", systemImage: "applewatch") }
            }
            Button { Task { await model.pushToGarmin(t) } } label: {
                Label(model.pushDisabledReason(for: t) ?? "Push to Garmin Connect", systemImage: "arrow.up.circle")
            }
            .disabled(model.pushDisabledReason(for: t) != nil)
            Button(role: .destructive) { pendingDelete = t } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder private var importSection: some View {
        Section {
            Button { showingImport = true } label: {
                Label("Import from Garmin Connect", systemImage: "square.and.arrow.down")
            }
            .disabled(model.garminDisabledReason != nil)
            .accessibilityIdentifier("workouts-import")
        } footer: {
            if let reason = model.garminDisabledReason { Text(reason) }
        }
    }
}

/// One library row: sport symbol, name + Garmin badge, summary line, weekday chips.
struct WorkoutLibraryRow: View {
    let template: WorkoutTemplate
    let pending: Bool
    let busy: Bool
    private let theme = JITheme.native

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: WorkoutFormat.sportSymbol(template.hasStrength ? .strength : (template.effectiveSegments.first?.sport ?? .running)))
                .font(.title3)
                .foregroundStyle(theme.color(.muted))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { title; badge }
                    VStack(alignment: .leading, spacing: 4) { title; badge }
                }
                Text(WorkoutFormat.summary(template)).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                let days = WorkoutFormat.weekdays(template.weekdays)
                if !days.isEmpty || pending {
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { d in
                            Text(d).jiFont(.caption, weight: .semibold)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(theme.color(.info).opacity(0.18)))
                                .foregroundStyle(theme.color(.info))
                        }
                        if pending {
                            Label("Waiting to sync", systemImage: "clock.arrow.circlepath")
                                .jiFont(.caption).foregroundStyle(theme.color(.muted))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if busy { ProgressView() }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the editor")
    }

    private var title: some View {
        Text(template.name).foregroundStyle(theme.color(.text)).lineLimit(2)
    }

    private var badge: some View {
        let state = template.garminState
        return Text(WorkoutFormat.garminLabel(state))
            .jiFont(.caption, weight: .semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(theme.color(.muted).opacity(0.5), lineWidth: 1))
            .foregroundStyle(state == .outdated ? theme.color(.reduced) : theme.color(.muted))
            .accessibilityLabel(WorkoutFormat.garminAccessibility(state))
            .fixedSize()
    }
}
