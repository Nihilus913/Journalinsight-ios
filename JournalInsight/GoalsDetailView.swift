//
//  GoalsDetailView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData

struct GoalsDetailView: View {
    @Query(sort: \Goal.targetDate) private var goals: [Goal]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddGoal = false

    var body: some View {
        List {
            if goals.isEmpty {
                ContentUnavailableView(
                    "No Goals Yet",
                    systemImage: "target",
                    description: Text("Tap + to add your first goal.")
                )
            }

            ForEach(goals) { goal in
                GoalRowView(goal: goal)
            }
            .onDelete(perform: deleteGoals)
        }
        .navigationTitle("Goals")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddGoal = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            AddGoalSheet()
        }
    }

    private func deleteGoals(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(goals[index])
        }
    }
}

struct GoalRowView: View {
    @Bindable var goal: Goal

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goal.title)
                .font(.headline)
            HStack {
                ProgressView(value: goal.progress)
                    .tint(progressColor)
                Text("\(Int(goal.progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            HStack {
                Text("Target: \(Self.dateFormatter.string(from: goal.targetDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Stepper("", value: $goal.progress, in: 0...1, step: 0.1)
                    .labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }

    private var progressColor: Color {
        if goal.progress >= 1.0 { return .green }
        if goal.targetDate < Date() { return .red }
        return AppTheme.primaryColor
    }
}

struct AddGoalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Goal title", text: $title)
                }
                Section("Target Date") {
                    DatePicker("Date", selection: $targetDate, displayedComponents: .date)
                }
            }
            .navigationTitle("New Goal")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let goal = Goal(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            targetDate: targetDate
                        )
                        modelContext.insert(goal)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GoalsDetailView()
    }
    .modelContainer(for: Goal.self, inMemory: true)
}
