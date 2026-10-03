import SwiftUI
import JICore
import JIDesign

/// W4-L3, mirrors `mobile/src/components/goals/GoalDatePicker.tsx`'s controlled string-or-nil
/// contract for a goal's optional target date. Uses SwiftUI's native `DatePicker` (a real
/// calendar) rather than porting the RN month-grid math — same "pick one date or clear it" result,
/// different picker chrome.
public struct GoalDatePicker: View {
    @Environment(\.jiTheme) private var theme
    @Binding var value: String?

    public init(value: Binding<String?>) { self._value = value }

    /// W-KEYS K3 (scout risk 5): the picker shows the device's calendar, so the stored day goes
    /// through the phone-zone `DayKey` both ways (a UTC midnight showed the day before west of UTC).
    private var selection: Binding<Date> {
        Binding(
            get: { goalDatePickerDate(value) ?? Date() },
            set: { value = goalDatePickerISO($0) }
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
                    .foregroundStyle(theme.color(.danger))
                    .accessibilityLabel("Clear target date")
                    .accessibilityIdentifier("goal-clear-target-date")
            }
        }
    }
}

/// `yyyy-MM-dd` → the phone-zone midnight the `DatePicker` shows as that day; nil when unreadable.
nonisolated func goalDatePickerDate(_ iso: String?, in zone: TimeZone = DayKey.zone) -> Date? {
    iso.flatMap { DayKey(iso: $0) }?.startDate(in: zone)
}

/// The picked instant → its phone-zone day.
nonisolated func goalDatePickerISO(_ date: Date, in zone: TimeZone = DayKey.zone) -> String {
    DayKey(date: date, in: zone).iso
}
