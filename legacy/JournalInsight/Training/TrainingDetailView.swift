import SwiftUI
import SwiftData

struct TrainingDetailView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var entries: [WorkoutEntry]
    @State private var showingLogSheet = false

    private var streak: Int { TrainingStreakCalculator.currentStreak(from: entries) }
    private var bestStreak: Int { TrainingStreakCalculator.bestStreak(from: entries) }

    private var nextMilestone: Int? {
        TrainingStreakCalculator.milestones.first { $0 > streak }
    }

    private var isMilestone: Bool {
        TrainingStreakCalculator.milestones.contains(streak)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                if isMilestone && streak > 0 {
                    HStack {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(TrainingStreakCalculator.milestoneLabel(for: streak))
                            .font(.headline)
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.yellow.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .symbolEffect(.bounce, value: streak)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current streak")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(streak)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                        Text(streak == 1 ? "day" : "days")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    Text("Best: \(bestStreak) days")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let next = nextMilestone {
                    let progress = Double(streak) / Double(next)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next milestone: \(TrainingStreakCalculator.milestoneLabel(for: next))")
                            .font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: progress)
                            .tint(.orange)
                        Text("\(next - streak) sessions to go")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Milestones")
                        .font(.headline)
                    ForEach(TrainingStreakCalculator.milestones, id: \.self) { m in
                        HStack {
                            Image(systemName: streak >= m ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(streak >= m ? .green : .secondary)
                            Text(TrainingStreakCalculator.milestoneLabel(for: m))
                            Spacer()
                            Text("\(m)d")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent workouts")
                            .font(.headline)
                        ForEach(entries.prefix(10)) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.subheadline.weight(.medium))
                                    HStack(spacing: 6) {
                                        Text("\(entry.durationSec / 60) min")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Label(entry.source.rawValue, systemImage: entry.source.icon)
                                            .font(.caption2)
                                            .foregroundStyle(entry.source.color)
                                    }
                                }
                                Spacer()
                                if !entry.exercises.isEmpty {
                                    Text("\(entry.exercises.count) exercises")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }

                Button {
                    showingLogSheet = true
                } label: {
                    Label("Log workout", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingLogSheet) {
            ManualWorkoutLogSheet()
        }
    }
}

#Preview {
    NavigationStack {
        TrainingDetailView()
    }
    .modelContainer(for: WorkoutEntry.self, inMemory: true)
}
