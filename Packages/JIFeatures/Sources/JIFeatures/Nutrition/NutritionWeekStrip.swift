import SwiftUI
import JICore
import JIDesign

/// Day-nav strip (W3a-L2, mirrors `mobile/src/components/nutrition/NutritionWeekStrip.tsx`) —
/// selecting a chip re-queries that date's meal detail in place (`NutritionViewModel.selectDate`).
public struct NutritionWeekStrip: View {
    let days: [NutritionDailyRow]
    let selectedDate: String
    let onSelect: (String) -> Void

    public init(days: [NutritionDailyRow], selectedDate: String, onSelect: @escaping (String) -> Void) {
        self.days = days; self.selectedDate = selectedDate; self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(days.sorted { $0.date < $1.date }, id: \.date) { day in
                    Button { onSelect(day.date) } label: { chip(for: day) }
                        .buttonStyle(.pressableScale)
                        .accessibilityLabel(accessibilityLabel(for: day))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(for day: NutritionDailyRow) -> some View {
        let selected = day.date == selectedDate
        return VStack(spacing: 4) {
            Text(NutritionWeekStrip.weekdayLabel(day.date)).font(.caption2).foregroundStyle(JIColor.muted)
            Circle()
                .fill(day.kcalConsumed == nil ? JIColor.surface3 : JIColor.info)
                .frame(width: 6, height: 6)
            Text(day.kcalConsumed.map { "\(Int($0))" } ?? "—")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(JIColor.text)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(selected ? JIColor.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? JIColor.info : .clear, lineWidth: 1))
    }

    private func accessibilityLabel(for day: NutritionDailyRow) -> String {
        let kcal = day.kcalConsumed.map { "\(Int($0)) kcal" } ?? "no data"
        return "\(day.date), \(kcal)"
    }

    /// Not `nonisolated` (this type stays `@MainActor` under JIFeatures' default isolation) but
    /// pure — a plain function so it stays independently testable, mirroring `StatChip`'s label
    /// builders (JIDesign).
    static func weekdayLabel(_ isoDate: String) -> String {
        guard let date = NutritionWeekStrip.dayFormatter.date(from: isoDate) else { return isoDate }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
