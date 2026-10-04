import SwiftUI
import JICore
import JIDesign

/// W-B92 C-5 (Bevel gap BP-1) — the Planner's Month tab (mockup docs/waves/mockups/bevel/BP-1.html,
/// HT repo): SESSIONS DONE card ("3 of 26 owed in September", Q1 partial apart), the 7-column
/// Mon-first grid (glyph per state + the session letter), month ‹ ›, legend. A past day opens a
/// read-only record (Q2); today / a future day opens the existing day sheet (`onEditDay`).
public struct TrainingMonthView: View {
    @Bindable var model: TrainingMonthModel
    let onEditDay: (_ weekday: Int) -> Void
    @State private var record: TrainingCalendarDay?
    private let theme = JITheme.native
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    public init(model: TrainingMonthModel, onEditDay: @escaping (_ weekday: Int) -> Void) {
        self.model = model; self.onEditDay = onEditDay
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthNav
            if let m = model.data {
                Surface(level: 1, padding: JISpacing.cardPadding) { summaryCard(m) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("training-month-summary")
                Surface(level: 1, padding: JISpacing.s3) { grid(m) }
                    .padding(.top, JISpacing.s3)
                legend.padding(.top, JISpacing.s3)
            } else {
                Text(model.isLoading ? "Loading…" : "— No data").jiFont(.body).foregroundStyle(theme.color(.muted))
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, JISpacing.s3)
            }
            Text("Tap a day to see its session. Future days can be changed; past days are a record.")
                .jiFont(.caption).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s3)
        }
        .task { if model.data == nil { await model.load() } }
        .sheet(item: $record) { day in TrainingMonthDayRecord(day: day) }
        .accessibilityIdentifier("training-month")
    }

    private var monthNav: some View {
        HStack {
            Button { Task { await model.shift(by: -1) } } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month").accessibilityIdentifier("training-month-prev")
            Spacer()
            Text(trainingMonthTitle(model.month)).jiFont(.cardTitle, weight: .semibold).foregroundStyle(theme.color(.text))
                .accessibilityIdentifier("training-month-title")
            Spacer()
            Button { Task { await model.shift(by: 1) } } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month").accessibilityIdentifier("training-month-next")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, JISpacing.s4).padding(.bottom, JISpacing.s2)
    }

    private func summaryCard(_ m: TrainingCalendarMonth) -> some View {
        VStack(alignment: .leading, spacing: JISpacing.s2) {
            Text("SESSIONS DONE").jiFont(.micro, weight: .bold).foregroundStyle(theme.color(.muted))
            Text(trainingMonthHeadline(m)).jiFont(.cardTitleLarge, weight: .semibold).foregroundStyle(theme.color(.text))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = trainingMonthDetail(m) {
                Text(detail).jiFont(.subheadline).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
            }
            if let sync = trainingMonthSyncLine(m) {
                Text(model.isOffline ? "\(sync) · offline" : sync).jiFont(.caption).foregroundStyle(theme.color(.muted))
            } else if model.isOffline {
                Text("Offline — planned days only").jiFont(.caption).foregroundStyle(theme.color(.muted))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func grid(_ m: TrainingCalendarMonth) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                Text(d).jiFont(.caption, weight: .bold).foregroundStyle(theme.color(.muted)).accessibilityHidden(true)
            }
            ForEach(Array(trainingMonthGrid(m).enumerated()), id: \.offset) { _, cell in
                if let day = cell { dayCell(day, today: m.today) } else { Color.clear.frame(height: 48) }
            }
        }
    }

    private func color(_ s: TrainingCalendarDay.State) -> Color {
        switch s {
        case .done: theme.color(.go)
        case .partial: theme.color(.reduced)
        case .missed: theme.color(.danger)
        case .unknown, .planned, .rest: theme.color(.muted)
        }
    }

    private func dayCell(_ day: TrainingCalendarDay, today: String) -> some View {
        let isToday = day.date == today
        return Button {
            if model.isReadOnly(day) {
                record = day
            } else if let wd = TrainingCalendarMonth.dates(of: String(day.date.prefix(7)))?.first(where: { $0.iso == day.date })?.weekday {
                onEditDay(wd)
            }
        } label: {
            VStack(spacing: 2) {
                Text(String(Int(day.date.suffix(2)) ?? 0)).jiFont(.caption, weight: isToday ? .bold : .regular)
                    .foregroundStyle(theme.color(isToday ? .text : .muted))
                Text(trainingMonthGlyph(day.state)).jiFont(.body, weight: .bold).foregroundStyle(color(day.state))
                Text(TrainingCalendarPlanned.letter(forType: day.planned.type) ?? " ").jiFont(.micro, weight: .bold)
                    .foregroundStyle(theme.color(.muted))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 8).stroke(isToday ? theme.color(.text) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trainingMonthCellLabel(day))
        .accessibilityHint(model.isReadOnly(day) ? "Shows what was planned and done" : "Opens the day to change it")
        .accessibilityIdentifier("training-month-day-\(day.date)")
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("● Done   ◐ Partial   ○ Planned   ✕ Missed   ? Not synced   – Rest")
            Text("S strength · I intervals · Z zone 2")
        }
        .jiFont(.caption).foregroundStyle(theme.color(.muted))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, JISpacing.s4)
        .accessibilityIdentifier("training-month-legend")
    }
}

/// Q2: a past day's record — what was planned, what was logged, the state. No Change day.
struct TrainingMonthDayRecord: View {
    let day: TrainingCalendarDay
    private let theme = JITheme.native

    var body: some View {
        NavigationStack {
            List {
                Section("Planned") {
                    Text(day.planned.isOwed ? day.planned.name : "Rest").jiFont(.body)
                    if day.planned.source == "snapshot" || day.planned.source == "device" {
                        Text("As planned that day").jiFont(.caption).foregroundStyle(theme.color(.muted))
                    }
                }
                Section("Logged") {
                    if day.activities.isEmpty {
                        Text(day.state == .unknown ? "Not synced yet" : "No workout logged").foregroundStyle(theme.color(.muted))
                    }
                    ForEach(day.activities, id: \.activityId) { a in
                        HStack {
                            Text((a.type ?? "workout").replacingOccurrences(of: "_", with: " ").capitalized)
                            Spacer()
                            if let s = a.durationSec { Text("\(s / 60) min").foregroundStyle(theme.color(.muted)) }
                            if let z = a.z2Share { Text("Z2 \(Int((z * 100).rounded())) %").foregroundStyle(theme.color(.muted)) }
                        }
                    }
                }
                Section {
                    Text(trainingMonthStateWord(day.state).capitalized).jiFont(.body, weight: .semibold)
                    Text("Past days are read-only.").jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
            }
            .navigationTitle(trainingMonthCellLabel(day).components(separatedBy: ",").first ?? day.date)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .accessibilityIdentifier("training-month-record")
        }
        .presentationDetents([.medium, .large])
    }
}
