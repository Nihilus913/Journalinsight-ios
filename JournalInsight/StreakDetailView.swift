//
//  StreakDetailView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData

struct StreakDetailView: View {
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @State private var showCelebration = false

    private var currentStreak: Int {
        StreakCalculator.currentStreak(from: entries)
    }

    private var bestStreak: Int {
        StreakCalculator.bestStreak(from: entries)
    }

    private var preferredTimeOfDay: String {
        StreakCalculator.preferredTimeOfDay(from: entries)
    }

    private static let milestones = [7, 14, 30, 50, 100, 200, 365]

    private var nextMilestone: Int? {
        Self.milestones.first(where: { $0 > currentStreak })
    }

    private var reachedMilestones: [Int] {
        Self.milestones.filter { $0 <= currentStreak }
    }

    private var isOnMilestone: Bool {
        Self.milestones.contains(currentStreak)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Celebration overlay
                if showCelebration {
                    celebrationBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                VStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(currentStreak > 0 ? .orange : .gray)
                        .symbolEffect(.bounce, value: showCelebration)
                    Text("\(currentStreak)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                    Text("day streak")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                Divider().padding(.horizontal)

                VStack(spacing: 16) {
                    HStack {
                        Label("Best Streak", systemImage: "trophy.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(bestStreak) days")
                            .bold()
                    }

                    HStack {
                        Label("Most Active", systemImage: "clock.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(preferredTimeOfDay)
                            .bold()
                    }

                    HStack {
                        Label("Total Entries", systemImage: "book.closed.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(entries.count)")
                            .bold()
                    }
                }
                .padding(.horizontal)

                // Milestones section (Feature #10)
                Divider().padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Milestones")
                        .font(.headline)
                        .padding(.horizontal)

                    if let next = nextMilestone {
                        HStack {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.orange)
                            Text("Next: \(next) days")
                                .foregroundColor(.secondary)
                            Spacer()
                            let progress = Double(currentStreak) / Double(next)
                            ProgressView(value: progress)
                                .frame(width: 100)
                                .tint(.orange)
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    ForEach(Self.milestones, id: \.self) { milestone in
                        let reached = currentStreak >= milestone
                        HStack {
                            Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(reached ? .green : .gray)
                            Text("\(milestone) Days")
                                .font(.subheadline)
                                .foregroundColor(reached ? .primary : .secondary)
                            Spacer()
                            Text(milestoneLabel(for: milestone))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Streak")
        .inlineNavigationTitle()
        .onAppear {
            if isOnMilestone {
                withAnimation(.spring(response: 0.5)) {
                    showCelebration = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { showCelebration = false }
                }
            }
        }
    }

    @ViewBuilder
    private var celebrationBanner: some View {
        VStack(spacing: 8) {
            Text("Congratulations!")
                .font(.title2.bold())
            Text("You've reached a \(currentStreak)-day streak!")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.orange.opacity(0.3), .yellow.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(16)
    }

    private func milestoneLabel(for milestone: Int) -> String {
        switch milestone {
        case 7: return "One Week"
        case 14: return "Two Weeks"
        case 30: return "One Month"
        case 50: return "Fifty Days"
        case 100: return "Century"
        case 200: return "Double Century"
        case 365: return "Full Year"
        default: return "\(milestone) Days"
        }
    }
}

#Preview {
    NavigationStack {
        StreakDetailView()
    }
    .modelContainer(for: JournalEntry.self, inMemory: true)
}
