//
//  SessionDetailView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData
import Charts

struct SessionDetailView: View {
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]

    private var totalEntries: Int { entries.count }

    private var totalMinutes: Int {
        Int(entries.reduce(0) { $0 + $1.duration }) / 60
    }

    private var averageDurationMinutes: Int {
        guard !entries.isEmpty else { return 0 }
        return totalMinutes / entries.count
    }

    private var longestSessionMinutes: Int {
        Int((entries.map(\.duration).max() ?? 0) / 60)
    }

    private var entriesThisWeek: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return entries.filter { $0.date >= startOfWeek }.count
    }

    // Chart data: entries per day for last 7 days
    private var weeklyChartData: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { daysAgo -> (Date, Int)? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return nil }
            let count = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }.count
            return (date, count)
        }
    }

    // Chart data: total minutes per day for last 7 days
    private var durationChartData: [(date: Date, minutes: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { daysAgo -> (Date, Double)? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return nil }
            let total = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
                .reduce(0.0) { $0 + $1.duration / 60.0 }
            return (date, total)
        }
    }

    // Mood distribution
    private var moodDistribution: [(mood: Mood, count: Int)] {
        Mood.allCases.compactMap { mood in
            let count = entries.filter { $0.mood == mood }.count
            return count > 0 ? (mood, count) : nil
        }
    }

    var body: some View {
        List {
            Section("Overview") {
                StatRow(label: "Total Entries", value: "\(totalEntries)")
                StatRow(label: "Total Time", value: "\(totalMinutes) min")
                StatRow(label: "Average Duration", value: "\(averageDurationMinutes) min")
                StatRow(label: "Longest Session", value: "\(longestSessionMinutes) min")
            }

            Section("This Week") {
                StatRow(label: "Entries", value: "\(entriesThisWeek)")
            }

            // Feature #9: Charts
            if !entries.isEmpty {
                Section("Entries This Week") {
                    Chart(weeklyChartData, id: \.date) { item in
                        BarMark(
                            x: .value("Day", item.date, unit: .day),
                            y: .value("Entries", item.count)
                        )
                        .foregroundStyle(AppTheme.primaryColor.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                    .frame(height: 180)
                }

                Section("Duration Trend (min)") {
                    Chart(durationChartData, id: \.date) { item in
                        LineMark(
                            x: .value("Day", item.date, unit: .day),
                            y: .value("Minutes", item.minutes)
                        )
                        .foregroundStyle(AppTheme.accentColor)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Day", item.date, unit: .day),
                            y: .value("Minutes", item.minutes)
                        )
                        .foregroundStyle(AppTheme.accentColor.opacity(0.15))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                    .frame(height: 180)
                }

                if !moodDistribution.isEmpty {
                    Section("Mood Distribution") {
                        Chart(moodDistribution, id: \.mood) { item in
                            BarMark(
                                x: .value("Mood", item.mood.emoji),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(colorForMood(item.mood).gradient)
                            .cornerRadius(4)
                        }
                        .frame(height: 160)
                    }
                }

                Section("Recent Entries") {
                    ForEach(entries.prefix(5)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if let mood = entry.mood {
                                    Text(mood.emoji)
                                }
                                Text(entry.date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(entry.text ?? "")
                                .lineLimit(2)
                            Text("\(Int(entry.duration) / 60) min")
                                .font(.caption2)
                                .foregroundColor(AppTheme.primaryColor)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Session KPIs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func colorForMood(_ mood: Mood) -> Color {
        switch mood {
        case .great: return .green
        case .good: return .teal
        case .okay: return .yellow
        case .bad: return .orange
        case .terrible: return .red
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .bold()
                .foregroundColor(AppTheme.primaryColor)
        }
    }
}

#Preview {
    NavigationStack {
        SessionDetailView()
    }
    .modelContainer(for: JournalEntry.self, inMemory: true)
}
