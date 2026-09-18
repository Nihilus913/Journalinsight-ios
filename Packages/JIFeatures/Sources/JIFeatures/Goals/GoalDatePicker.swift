import SwiftUI
import JIDesign

/// W4-L3, mirrors `mobile/src/components/goals/GoalDatePicker.tsx`'s controlled string-or-nil
/// contract for a goal's optional target date. Uses SwiftUI's native `DatePicker` (a real
/// calendar) rather than porting the RN month-grid math — same "pick one date or clear it" result,
/// different picker chrome.
public struct GoalDatePicker: View {
    @Binding var value: String?

    public init(value: Binding<String?>) { self._value = value }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var selection: Binding<Date> {
        Binding(
            get: { value.flatMap(Self.formatter.date(from:)) ?? Date() },
            set: { value = Self.formatter.string(from: $0) }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker("Target date", selection: selection, displayedComponents: .date)
                .labelsHidden()
                .accessibilityLabel(value.map { "Target date, \($0)" } ?? "Target date, not set")
                .accessibilityIdentifier("goal-target-date")
            if value != nil {
                Button("Clear date") { value = nil }
                    .font(.caption.bold())
                    .foregroundStyle(JIColor.danger)
                    .accessibilityLabel("Clear target date")
                    .accessibilityIdentifier("goal-clear-target-date")
            }
        }
    }
}
