import SwiftUI
import JICore
import JIDesign

public nonisolated func trainingWeekStatusText(_ s: TrainingWeekSummary) -> String {
    guard s.planTotal > 0 else { return "No plan yet" }
    if s.matchesPlan { return "Matches plan" }
    let open = s.planTotal - s.assigned
    return "\(open) session\(open == 1 ? "" : "s") not on a day yet"
}

/// Interval rows name the user's own cap (W4, optional) — never a default number.
public nonisolated func trainingWeekIntervalCaption(hrCapBpm: Int?) -> String {
    hrCapBpm.map { "Your cap \($0)" } ?? "No cap set"
}

/// Sessions the hub can take a weekday for (a real plan_session id — B-52's rule).
public func assignableSessions(planSessions: [PlanSessionOut], exercises: [Exercise]) -> [TrainingSessionRef] {
    weekSpine(planSessions: planSessions, exercises: exercises).compactMap { e in
        e.id.map { TrainingSessionRef(id: $0, name: e.name, weekday: e.weekday) }
    }
}

/// B-57 W5 board 3/02 "Your week". W-B40 L3 (B-82): day-first — every row opens that day's
/// preview (`TrainingDaySheet`), where Change / Add pick from the plan sessions and the B-40
/// workout library. Writes go through `TrainingViewModel.changeDay` (Outbox first, B-52), so each
/// change is saved on tap — there is no separate Save step.
public struct TrainingWeekView: View {
    @Environment(\.dynamicTypeSize) private var typeSize   // W-FIX11 H1-17
    @Bindable private var model: TrainingViewModel
    @State private var dayPreview: TrainingDayRef?
    @Environment(\.gateSettings) private var gateSettings
    /// B-33: a screen root reads the theme it installs (see `TrainingView`).
    private let theme = JITheme.native

    public init(model: TrainingViewModel) { self.model = model }

    private var summary: TrainingWeekSummary { model.weekSummary }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text("Give each day a session from your plan or your workout library.")
                    .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.bottom, JISpacing.s3)
                Surface(level: 1, padding: JISpacing.cardPadding, tint: summary.matchesPlan ? theme.color(.go) : nil) { summaryCard }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("training-week-summary")
                JISectionHeader("Sessions")
                Surface(level: 1, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(summary.days) { day in
                            if day.weekday > 0 { JIRowDivider().padding(.leading, 0) }
                            dayRow(day).padding(.vertical, JISpacing.s3)
                        }
                        if summary.days.isEmpty {
                            Text("— No data").jiFont(.body).foregroundStyle(theme.color(.muted))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, JISpacing.s3)
                        }
                    }
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
                }
                Text("Tap a day to see its session and change it. The Training count follows the strength days.")
                    .jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s3)
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiGlassBackButton()
        .jiTheme(.native)
        .navigationTitle("Your week")
        .onAppear { model.screenAppeared() }
        .sheet(item: $dayPreview) { ref in TrainingDaySheet(model: model, weekday: ref.weekday) }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: JISpacing.s2) {
            Text("STRENGTH DAYS").jiFont(.micro, weight: .bold).foregroundStyle(theme.color(.muted))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary.planTotal > 0 ? "\(summary.assigned)" : "—").jiNumeral(.numeralLarge, weight: .heavy, tint: .text)
                Text(summary.planTotal > 0 ? "of \(summary.planTotal) in your plan" : "No plan yet")
                    .jiFont(.body).foregroundStyle(theme.color(.muted))
            }
            if summary.planTotal > 0 {
                Label(trainingWeekStatusText(summary), systemImage: summary.matchesPlan ? "checkmark" : "exclamationmark.circle")
                    .jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(summary.matchesPlan ? .go : .reduced))
                HStack(spacing: 4) {
                    ForEach(0..<summary.planTotal, id: \.self) { i in
                        Capsule().fill(theme.color(i < summary.assigned ? .go : .nested)).frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowLabel(_ day: TrainingWeekDay, pending: Bool) -> some View {
        let titles = model.dayPreview(weekday: day.weekday).entries.map(\.title)
        // W-FIX11 H1-17: at AX sizes the weekday sits above the title (Today / Training already
        // stack there) — side by side the title broke mid-word ("Up-per", "Zone / 2 / 40").
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: JISpacing.s3))
        return layout {
            Text(trainingWeekdayShortNames[day.weekday]).jiFont(.body, weight: day.isToday ? .bold : .regular)
                .foregroundStyle(theme.color(day.isToday ? .text : .muted)).frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(titles.isEmpty ? "Rest" : titles.joined(separator: " + ")).jiFont(.body)
                    .foregroundStyle(theme.color(titles.isEmpty ? .muted : .text))
                    .fixedSize(horizontal: false, vertical: true)
                if day.kind == .interval {
                    Text(trainingWeekIntervalCaption(hrCapBpm: gateSettings.hrCapBpm)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                if pending { Text("Waiting to sync").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: JISpacing.s2)
                Text(day.kind.rawValue).jiFont(.caption, weight: .bold).foregroundStyle(theme.color(.muted))
                    .accessibilityHidden(true)
            }
        }
    }

    private func dayRow(_ day: TrainingWeekDay) -> some View {
        let entries = model.dayPreview(weekday: day.weekday).entries
        let pending = entries.contains { model.isPending($0) }
        let label = trainingWeekDayAccessibilityLabel(day) + (pending ? ", waiting to sync" : "")
        return Button { dayPreview = TrainingDayRef(weekday: day.weekday) } label: { JIChevronRow { rowLabel(day, pending: pending) } }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine).accessibilityLabel(label)
            .accessibilityHint("Shows \(planWeekdayNames[day.weekday])'s session")
            .accessibilityIdentifier("training-week-row-\(day.weekday)")
    }
}
