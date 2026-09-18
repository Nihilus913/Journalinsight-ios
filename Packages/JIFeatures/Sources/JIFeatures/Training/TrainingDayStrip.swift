import SwiftUI
import JICore
import JIDesign

/// Trained/not-trained status for one `DailyKpiRow`, keyed off `kcal_burned_active` (oracle:
/// `trainingDayStatus` in `TrainingDayStrip.tsx`) — a proxy for "trained that day" already present
/// on every gate row, rather than a separate per-date activities fetch just to color 7 dots.
nonisolated public enum TrainingDayStatus: Equatable, Sendable { case future, neutral, good, miss }

/// Same 300-kcal floor as the RN oracle (`SESSION_KCAL_FLOOR`) — a UX judgment call on data
/// already in hand, not a literature-grounded figure.
nonisolated public let sessionKcalFloor: Double = 300

nonisolated public func trainingDayStatus(kcalBurnedActive: Double?, isFuture: Bool) -> TrainingDayStatus {
    if isFuture { return .future }
    guard let kcalBurnedActive else { return .neutral } // not synced yet — no judgment (rule 5)
    return kcalBurnedActive >= sessionKcalFloor ? .good : .miss
}

/// Top-of-screen day navigator (oracle: `TrainingDayStrip.tsx`). Reads `gate.daily` — already
/// fetched for `GateDetailCard` — rather than firing a separate request.
public struct TrainingDayStrip: View {
    let daily: [DailyKpiRow]
    let selectedDate: String
    let today: String
    let onSelect: (String) -> Void

    public init(daily: [DailyKpiRow], selectedDate: String, today: String = String(Date().ISO8601Format().prefix(10)), onSelect: @escaping (String) -> Void) {
        self.daily = daily; self.selectedDate = selectedDate; self.today = today; self.onSelect = onSelect
    }

    private var trainedCount: Int {
        daily.filter { trainingDayStatus(kcalBurnedActive: $0.values["kcal_burned_active"] ?? nil, isFuture: $0.date > today) == .good }.count
    }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Text(daily.isEmpty ? "This week" : "This week · \(trainedCount)/\(daily.count) trained")
                    .font(.caption.weight(.semibold)).foregroundStyle(JIColor.muted)
                if daily.isEmpty {
                    Text("No training data yet.").font(.footnote).foregroundStyle(JIColor.muted)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(daily, id: \.date) { row in dayCell(row) }
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ row: DailyKpiRow) -> some View {
        let status = trainingDayStatus(kcalBurnedActive: row.values["kcal_burned_active"] ?? nil, isFuture: row.date > today)
        let selected = row.date == selectedDate
        return Button { onSelect(row.date) } label: {
            VStack(spacing: 4) {
                Text(dow(row.date)).font(.caption2).foregroundStyle(JIColor.muted)
                Text(String(row.date.suffix(2)))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(row.date == today ? JIColor.info : JIColor.text)
                Circle().fill(dotColor(status)).frame(width: 6, height: 6)
            }
            .padding(8)
            .background(selected ? JIColor.surface3 : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel("\(row.date)\(row.date == today ? ", today" : "")")
        .accessibilityValue(status == .good ? "trained" : status == .miss ? "not trained" : status == .future ? "upcoming" : "no data")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("training-day-\(row.date)")
    }

    private func dotColor(_ status: TrainingDayStatus) -> Color {
        switch status {
        case .good: JIColor.go
        case .miss: JIColor.danger
        case .neutral, .future: JIColor.mutedNested
        }
    }

    private func dow(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let d = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return "" }
        let symbols = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        return symbols[cal.component(.weekday, from: d) - 1]
    }
}
