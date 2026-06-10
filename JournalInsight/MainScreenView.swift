//
//  MainScreenView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData

// MARK: - Widget Types

enum WidgetSize: String, Codable {
    case small, medium, large
}

enum WidgetType: String, Codable, CaseIterable {
    case streak, session, questions, calendar, goals, training

    var title: String {
        switch self {
        case .streak: return "Streak Info"
        case .session: return "Session KPIs"
        case .questions: return "Questions Overview"
        case .calendar: return "Calendar Overview"
        case .goals: return "Goals Gantt Chart"
        case .training: return "Training"
        }
    }

    var systemImage: String {
        switch self {
        case .streak: return "flame.fill"
        case .session: return "chart.bar.fill"
        case .questions: return "questionmark.bubble.fill"
        case .calendar: return "calendar"
        case .goals: return "target"
        case .training: return "figure.strengthtraining.traditional"
        }
    }
}

struct WidgetItem: Identifiable, Codable {
    var id: String
    var type: WidgetType
    var size: WidgetSize

    init(id: String = UUID().uuidString, type: WidgetType, size: WidgetSize) {
        self.id = id
        self.type = type
        self.size = size
    }
}

struct WidgetRow: Identifiable {
    var id: String
    var items: [WidgetItem]
}

// MARK: - Main Screen

struct MainScreenView: View {
    @Query(sort: \JournalEntry.date, order: .reverse) private var journalEntries: [JournalEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDate: Date? = nil

    @AppStorage(StorageKeys.userName) private var userName: String = ""
    @State private var showingNamePrompt: Bool = false
    @State private var showingAddEntry: Bool = false
    @State private var searchText: String = ""
    @State private var entryToEdit: JournalEntry?

    @State private var widgets: [WidgetItem] = MainScreenView.loadWidgets()

    private var filteredEntries: [JournalEntry] {
        guard !searchText.isEmpty else { return journalEntries }
        let query = searchText.lowercased()
        return journalEntries.filter {
            $0.text.lowercased().contains(query) ||
            ($0.mood?.label.lowercased().contains(query) ?? false) ||
            $0.tags.contains(where: { $0.name.lowercased().contains(query) })
        }
    }

    private var widgetRows: [WidgetRow] {
        var rows: [WidgetRow] = []
        var tempWidgets = widgets
        while !tempWidgets.isEmpty {
            let widget = tempWidgets.removeFirst()
            if widget.size == .medium || widget.size == .large {
                rows.append(WidgetRow(id: widget.id, items: [widget]))
            } else {
                if let second = tempWidgets.first, second.size == .small {
                    let paired = tempWidgets.removeFirst()
                    rows.append(WidgetRow(id: "\(widget.id)-\(paired.id)", items: [widget, paired]))
                } else {
                    rows.append(WidgetRow(id: widget.id, items: [widget]))
                }
            }
        }
        return rows
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    widgetGrid

                    if !filteredEntries.isEmpty {
                        entriesList
                    }
                }
                .padding()
            }
            .background(.ultraThinMaterial)
            .navigationTitle(userName.isEmpty ? "Welcome Back!" : "Welcome Back, \(userName)!")
            .largeNavigationTitle()
            .searchable(text: $searchText, prompt: "Search entries...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
        .onAppear {
            if userName.isEmpty {
                showingNamePrompt = true
            }
            seedSampleDataIfNeeded()
        }
        .sheet(isPresented: $showingNamePrompt) {
            NamePromptSheet(userName: $userName, isPresented: $showingNamePrompt)
        }
        .sheet(isPresented: $showingAddEntry) {
            AddEntrySheet()
        }
        .sheet(item: $entryToEdit) { entry in
            EditEntrySheet(entry: entry)
        }
    }

    // MARK: - Widget Grid

    @ViewBuilder
    private var widgetGrid: some View {
        VStack(spacing: 16) {
            ForEach(widgetRows) { row in
                HStack(spacing: 16) {
                    ForEach(row.items) { widget in
                        if let index = widgets.firstIndex(where: { $0.id == widget.id }) {
                            NavigationLink(destination: destinationView(for: widget.type)) {
                                WidgetCardView(
                                    title: widget.type.title,
                                    systemImage: widget.type.systemImage,
                                    size: widget.size,
                                    entries: journalEntries,
                                    widgetType: widget.type
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                Button("Small") { widgets[index].size = .small; saveWidgets() }
                                Button("Medium") { widgets[index].size = .medium; saveWidgets() }
                                Button("Large") { widgets[index].size = .large; saveWidgets() }
                            }
                            .onDrag {
                                NSItemProvider(object: widget.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: WidgetDropDelegate(item: widget, items: $widgets, onDrop: saveWidgets))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Entries List (Feature #1 & #2)

    @ViewBuilder
    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(searchText.isEmpty ? "Recent Entries" : "Search Results")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(filteredEntries.prefix(10)) { entry in
                EntryRowView(entry: entry, onEdit: {
                    entryToEdit = entry
                }, onDelete: {
                    modelContext.delete(entry)
                })
            }
        }
    }

    @ViewBuilder
    private func destinationView(for type: WidgetType) -> some View {
        switch type {
        case .streak: StreakDetailView()
        case .session: SessionDetailView()
        case .questions: QuestionsDetailView()
        case .calendar: CalendarView(selectedDate: $selectedDate)
        case .goals: GoalsDetailView()
        case .training: TrainingDetailView()
        }
    }

    // MARK: - Persistence (Feature #14)

    private static func loadWidgets() -> [WidgetItem] {
        if let data = UserDefaults.standard.data(forKey: StorageKeys.widgetLayout),
           let decoded = try? JSONDecoder().decode([WidgetItem].self, from: data) {
            return decoded
        }
        return [
            WidgetItem(type: .streak, size: .small),
            WidgetItem(type: .session, size: .small),
            WidgetItem(type: .questions, size: .medium),
            WidgetItem(type: .calendar, size: .medium),
            WidgetItem(type: .goals, size: .medium)
        ]
    }

    private func saveWidgets() {
        if let data = try? JSONEncoder().encode(widgets) {
            UserDefaults.standard.set(data, forKey: StorageKeys.widgetLayout)
        }
    }

    private func seedSampleDataIfNeeded() {
        guard journalEntries.isEmpty else { return }
        let calendar = Calendar.current
        let samples = [
            JournalEntry(date: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date(), text: "Grateful for friends.", duration: 600, mood: .good),
            JournalEntry(date: Date(), text: "Reflecting on progress.", duration: 900, mood: .great)
        ]
        for entry in samples {
            modelContext.insert(entry)
        }
    }

    struct WidgetDropDelegate: DropDelegate {
        let item: WidgetItem
        @Binding var items: [WidgetItem]
        var onDrop: () -> Void

        func performDrop(info: DropInfo) -> Bool {
            guard let provider = info.itemProviders(for: [.text]).first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { nsString, _ in
                DispatchQueue.main.async {
                    if let idString = nsString as? String,
                       let fromIndex = items.firstIndex(where: { $0.id == idString }),
                       let toIndex = items.firstIndex(where: { $0.id == item.id }) {
                        let moved = items.remove(at: fromIndex)
                        items.insert(moved, at: toIndex)
                        onDrop()
                    }
                }
            }
            return true
        }
    }
}

// MARK: - Entry Row (Feature #1)

struct EntryRowView: View {
    let entry: JournalEntry
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let mood = entry.mood {
                    Text(mood.emoji)
                }
                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(entry.duration) / 60) min")
                    .font(.caption2)
                    .foregroundColor(AppTheme.primaryColor)
            }
            Text(entry.text)
                .lineLimit(2)
            if !entry.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(entry.tags) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.primaryColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
        .contextMenu {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Widget Card (Feature #11)

struct WidgetCardView: View {
    let title: String
    let systemImage: String
    let size: WidgetSize
    let entries: [JournalEntry]
    let widgetType: WidgetType

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(size == .large ? .largeTitle : .title2)
                .foregroundStyle(AppTheme.primaryColor)
            Text(title)
                .font(.subheadline)
                .multilineTextAlignment(.center)

            // Live data summaries
            switch widgetType {
            case .streak:
                let streak = StreakCalculator.currentStreak(from: entries)
                Text("\(streak) day\(streak == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .session:
                let count = entries.count
                Text("\(count) total entr\(count == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .calendar:
                let thisWeek = entriesThisWeek
                Text("\(thisWeek) this week")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .training:
                TrainingWidgetView(size: size)
            case .goals, .questions:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(height: size == .large ? 336 : 160)
        .background(Color.primary.opacity(0.1))
        .cornerRadius(20)
    }

    private var entriesThisWeek: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return entries.filter { $0.date >= startOfWeek }.count
    }
}

// MARK: - Name Prompt Sheet

struct NamePromptSheet: View {
    @Binding var userName: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("What's your name?").font(.title2)
            TextField("Your name", text: $userName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            Button("Continue") {
                if !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isPresented = false
                }
            }
            .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }
}

// MARK: - Add Entry Sheet (Features #3, #4, #7)

struct AddEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTags: [Tag]

    @State private var entryDate = Date()
    @State private var entryText = ""
    @State private var durationMinutes: Double = 10
    @State private var selectedMood: Mood? = nil
    @State private var selectedTags: Set<String> = []
    @State private var newTagName = ""

    // Timer state (Feature #4)
    @State private var useTimer = false
    @State private var timerRunning = false
    @State private var timerSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Entry Date", selection: $entryDate, displayedComponents: .date)
                }

                Section("Mood") {
                    HStack(spacing: 16) {
                        ForEach(Mood.allCases) { mood in
                            Button {
                                selectedMood = selectedMood == mood ? nil : mood
                            } label: {
                                VStack(spacing: 4) {
                                    Text(mood.emoji)
                                        .font(.title)
                                    Text(mood.label)
                                        .font(.caption2)
                                }
                                .padding(8)
                                .background(selectedMood == mood ? AppTheme.primaryColor.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Journal Text") {
                    TextEditor(text: $entryText)
                        .frame(minHeight: 120)
                }

                Section("Duration") {
                    Toggle("Use Timer", isOn: $useTimer)

                    if useTimer {
                        VStack(spacing: 12) {
                            Text(timerFormatted)
                                .font(.system(size: 48, weight: .medium, design: .monospaced))
                                .frame(maxWidth: .infinity)

                            HStack(spacing: 20) {
                                Button(timerRunning ? "Pause" : "Start") {
                                    toggleTimer()
                                }
                                .buttonStyle(.borderedProminent)

                                if timerSeconds > 0 {
                                    Button("Reset") {
                                        stopTimer()
                                        timerSeconds = 0
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        HStack {
                            Slider(value: $durationMinutes, in: 1...120, step: 1)
                            Text("\(Int(durationMinutes)) min")
                                .monospacedDigit()
                                .frame(width: 60)
                        }
                    }
                }

                Section("Tags") {
                    if !allTags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(allTags) { tag in
                                Button {
                                    if selectedTags.contains(tag.name) {
                                        selectedTags.remove(tag.name)
                                    } else {
                                        selectedTags.insert(tag.name)
                                    }
                                } label: {
                                    Text(tag.name)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedTags.contains(tag.name) ? AppTheme.primaryColor : Color.primary.opacity(0.1))
                                        .foregroundColor(selectedTags.contains(tag.name) ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        TextField("New tag", text: $newTagName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            if !allTags.contains(where: { $0.name == name }) {
                                let tag = Tag(name: name)
                                modelContext.insert(tag)
                            }
                            selectedTags.insert(name)
                            newTagName = ""
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("New Entry")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        stopTimer()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        stopTimer()
                        let duration: TimeInterval = useTimer ? TimeInterval(timerSeconds) : durationMinutes * 60
                        let entryTags = allTags.filter { selectedTags.contains($0.name) }
                        let entry = JournalEntry(
                            date: entryDate,
                            text: entryText.trimmingCharacters(in: .whitespacesAndNewlines),
                            duration: duration,
                            mood: selectedMood,
                            tags: entryTags
                        )
                        modelContext.insert(entry)
                        dismiss()
                    }
                    .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var timerFormatted: String {
        let mins = timerSeconds / 60
        let secs = timerSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func toggleTimer() {
        if timerRunning {
            stopTimer()
        } else {
            timerRunning = true
            timerTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled {
                        timerSeconds += 1
                    }
                }
            }
        }
    }

    private func stopTimer() {
        timerRunning = false
        timerTask?.cancel()
        timerTask = nil
    }
}

// MARK: - Edit Entry Sheet (Feature #1)

struct EditEntrySheet: View {
    @Bindable var entry: JournalEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allTags: [Tag]

    @State private var entryText: String = ""
    @State private var entryDate: Date = Date()
    @State private var durationMinutes: Double = 10
    @State private var selectedMood: Mood?
    @State private var selectedTags: Set<String> = []
    @State private var newTagName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Entry Date", selection: $entryDate, displayedComponents: .date)
                }

                Section("Mood") {
                    HStack(spacing: 16) {
                        ForEach(Mood.allCases) { mood in
                            Button {
                                selectedMood = selectedMood == mood ? nil : mood
                            } label: {
                                VStack(spacing: 4) {
                                    Text(mood.emoji)
                                        .font(.title)
                                    Text(mood.label)
                                        .font(.caption2)
                                }
                                .padding(8)
                                .background(selectedMood == mood ? AppTheme.primaryColor.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Journal Text") {
                    TextEditor(text: $entryText)
                        .frame(minHeight: 120)
                }

                Section("Duration") {
                    HStack {
                        Slider(value: $durationMinutes, in: 1...120, step: 1)
                        Text("\(Int(durationMinutes)) min")
                            .monospacedDigit()
                            .frame(width: 60)
                    }
                }

                Section("Tags") {
                    if !allTags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(allTags) { tag in
                                Button {
                                    if selectedTags.contains(tag.name) {
                                        selectedTags.remove(tag.name)
                                    } else {
                                        selectedTags.insert(tag.name)
                                    }
                                } label: {
                                    Text(tag.name)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedTags.contains(tag.name) ? AppTheme.primaryColor : Color.primary.opacity(0.1))
                                        .foregroundColor(selectedTags.contains(tag.name) ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        TextField("New tag", text: $newTagName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            if !allTags.contains(where: { $0.name == name }) {
                                let tag = Tag(name: name)
                                modelContext.insert(tag)
                            }
                            selectedTags.insert(name)
                            newTagName = ""
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        entry.text = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
                        entry.date = entryDate
                        entry.duration = durationMinutes * 60
                        entry.mood = selectedMood
                        entry.tags = allTags.filter { selectedTags.contains($0.name) }
                        dismiss()
                    }
                    .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                entryText = entry.text
                entryDate = entry.date
                durationMinutes = entry.duration / 60
                selectedMood = entry.mood
                selectedTags = Set(entry.tags.map(\.name))
            }
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y)
            subview.place(at: point, proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}

#Preview {
    MainScreenView()
        .modelContainer(for: [JournalEntry.self, Goal.self, Tag.self], inMemory: true)
        .frame(minWidth: 400, minHeight: 600)
}
