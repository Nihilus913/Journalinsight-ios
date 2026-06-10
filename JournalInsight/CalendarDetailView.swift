//
//  CalendarDetailView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData

struct CalendarView: View {
    @Binding var selectedDate: Date?
    @Query(sort: \JournalEntry.date) private var entries: [JournalEntry]
    @State private var scope: CalendarScope = .month
    @State private var navigationDate: Date = Date()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    var body: some View {
        ZStack {
            AppTheme.backgroundColor
                .ignoresSafeArea()

            VStack {
                // Month navigation (Feature #6)
                HStack {
                    Button {
                        navigate(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                    }

                    Spacer()

                    Text(Self.monthYearFormatter.string(from: navigationDate))
                        .font(.headline)

                    Spacer()

                    Button {
                        navigate(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                    }
                }
                .padding(.horizontal)

                Button("Today") {
                    withAnimation {
                        navigationDate = Date()
                        selectedDate = Date()
                    }
                }
                .font(.caption)
                .padding(.bottom, 4)

                Picker("View", selection: $scope) {
                    Text("Month").tag(CalendarScope.month)
                    Text("Work Week").tag(CalendarScope.workWeek)
                    Text("Full Week").tag(CalendarScope.fullWeek)
                    Text("2 Weeks").tag(CalendarScope.twoWeeks)
                    Text("4 Weeks").tag(CalendarScope.fourWeeks)
                }
                .pickerStyle(SegmentedPickerStyle())

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                    ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                        Text(day.prefix(2))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                    ForEach(datesToDisplay, id: \.self) { date in
                        VStack(spacing: 2) {
                            Text(Self.dayFormatter.string(from: date))
                                .font(.body)
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(Calendar.current.isDate(date, inSameDayAs: selectedDate ?? Date()) ? AppTheme.primaryColor.opacity(0.3) : Color.clear)
                                .clipShape(Circle())
                                .onTapGesture {
                                    selectedDate = date
                                }

                            let dayEntries = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                            if let firstMood = dayEntries.compactMap(\.mood).first {
                                Text(firstMood.emoji)
                                    .font(.system(size: 10))
                            } else if !dayEntries.isEmpty {
                                Circle()
                                    .fill(AppTheme.primaryColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut, value: scope)
                .animation(.easeInOut, value: navigationDate)
                .padding()

                if let selectedDate = selectedDate {
                    let dayEntries = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
                    if !dayEntries.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Entries for \(Self.fullFormatter.string(from: selectedDate))")
                                    .font(.headline)
                                ForEach(dayEntries) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            if let mood = entry.mood {
                                                Text(mood.emoji)
                                            }
                                            Text(entry.text)
                                                .lineLimit(3)
                                            Spacer()
                                        }
                                        Text("Duration: \(Int(entry.duration) / 60) min")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
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
                                    .padding(10)
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(8)
                                }
                            }
                            .padding()
                        }
                    } else {
                        Text("No entries for this day")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                } else {
                    Text("Select a day to view entries")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        .navigationTitle("Calendar Details")
        .inlineNavigationTitle()
    }

    // MARK: - Navigation (Feature #6)

    private func navigate(by amount: Int) {
        let calendar = Calendar.current
        switch scope {
        case .month:
            if let newDate = calendar.date(byAdding: .month, value: amount, to: navigationDate) {
                withAnimation { navigationDate = newDate }
            }
        case .workWeek, .fullWeek:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: amount, to: navigationDate) {
                withAnimation { navigationDate = newDate }
            }
        case .twoWeeks:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: amount * 2, to: navigationDate) {
                withAnimation { navigationDate = newDate }
            }
        case .fourWeeks:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: amount * 4, to: navigationDate) {
                withAnimation { navigationDate = newDate }
            }
        }
    }

    // MARK: - Helpers

    private var datesToDisplay: [Date] {
        let calendar = Calendar(identifier: .iso8601)

        switch scope {
        case .month:
            guard let monthRange = calendar.range(of: .day, in: .month, for: navigationDate),
                  let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: navigationDate)) else {
                return []
            }
            return monthRange.compactMap { day in
                calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
            }

        case .workWeek:
            guard let startOfWeek = startOfISOWeek(for: navigationDate, using: calendar) else { return [] }
            return (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }

        case .fullWeek:
            guard let startOfWeek = startOfISOWeek(for: navigationDate, using: calendar) else { return [] }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }

        case .twoWeeks:
            guard let startOfWeek = startOfISOWeek(for: navigationDate, using: calendar),
                  let startOfPeriod = calendar.date(byAdding: .day, value: -7, to: startOfWeek) else { return [] }
            return (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfPeriod) }

        case .fourWeeks:
            guard let startOfWeek = startOfISOWeek(for: navigationDate, using: calendar),
                  let startOfPeriod = calendar.date(byAdding: .day, value: -14, to: startOfWeek) else { return [] }
            return (0..<28).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfPeriod) }
        }
    }

    private func startOfISOWeek(for date: Date, using calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components)
    }
}

#Preview {
    NavigationStack {
        CalendarView(selectedDate: .constant(Date()))
    }
    .modelContainer(for: [JournalEntry.self, Tag.self], inMemory: true)
}
