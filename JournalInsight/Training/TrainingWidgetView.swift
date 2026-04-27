import SwiftUI
import SwiftData

struct TrainingWidgetView: View {
    let size: WidgetSize

    @Query(sort: \WorkoutEntry.date, order: .reverse) private var entries: [WorkoutEntry]

    @State private var recovery: RecoverySnapshot? = nil
    @AppStorage(StorageKeys.workoutDays) private var workoutDaysData: Data = Data()

    private var streak: Int { TrainingStreakCalculator.currentStreak(from: entries) }
    private var lastEntry: WorkoutEntry? { entries.first }

    private var isWorkoutDay: Bool {
        guard let days = try? JSONDecoder().decode([Int].self, from: workoutDaysData) else { return false }
        let weekday = Calendar.current.component(.weekday, from: .now)
        return days.contains(weekday)
    }

    private var daysSinceLabel: String {
        guard let last = lastEntry else { return "No workouts yet" }
        let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day ?? 0
        switch days {
        case 0: return "Trained today"
        case 1: return "Trained yesterday"
        default: return "\(days) days since last session"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
                Text("Training")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if streak > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(streak)")
                        .font(.title.weight(.bold))
                    Text(streak == 1 ? "day" : "days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("0")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(daysSinceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if isWorkoutDay, let r = recovery {
                Divider()
                HStack(spacing: 12) {
                    if let dur = r.sleepDurationSec {
                        Label(String(format: "%.0fh sleep", dur / 3600), systemImage: "moon.zzz")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let rhr = r.restingHR {
                        Label("\(Int(rhr)) bpm", systemImage: "heart")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, size == .small ? 0 : 4)
        .task {
            if isWorkoutDay && HealthKitPermissions.isAvailable {
                let reader = HealthKitReader()
                recovery = await reader.latestRecovery()
            }
        }
    }
}
