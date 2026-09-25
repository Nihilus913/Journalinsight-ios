import SwiftUI
import JICore
import JIDesign

#if canImport(WorkoutKit)
/// B-57 W1: the Training header's Watch line, from the Send-to-Watch state. `nil` (not wired)
/// makes no claim at all.
public nonisolated func trainingWatchLine(_ state: SendToWatchViewModel.State?) -> String? {
    guard let state else { return nil }
    switch state {
    case .sent: return "On your Watch"
    case .sending: return "Sending to your Watch…"
    case .idle, .loading, .authDenied, .error: return "Not on your Watch yet"
    }
}
#endif

/// W-FIX3 fixer BUG-44 (board 3/01): the header subtitle — "Full · Wed 23 Sep". The verdict word
/// leads only when the hub's verdict is today's (a stale or missing verdict makes no claim); the
/// date is the REAL device day (B-45 a).
public nonisolated struct TrainingSubtitle: Equatable, Sendable {
    public let word: String?
    public let tone: VerdictTone
    public let dateText: String
    public var text: String { word.map { "\($0) · \(dateText)" } ?? dateText }
}

public nonisolated func trainingSubtitle(verdict: String?, isStale: Bool, date: Date,
                                         locale: Locale = .autoupdatingCurrent,
                                         timeZone: TimeZone = .autoupdatingCurrent) -> TrainingSubtitle {
    let style = Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated).day().month(.abbreviated)
    let dateText = date.formatted(style)
    guard !isStale, let verdict, !verdict.isEmpty else { return TrainingSubtitle(word: nil, tone: .muted, dateText: dateText) }
    let parts = displayVerdictParts(verdictParts(verdict))
    return TrainingSubtitle(word: verdictUserWord(parts), tone: parts.tone, dateText: dateText)
}

/// W-FIX3 fixer BUG-44: one exercise line in the Training hero — "50.0 kg · 3 sets".
public nonisolated struct TrainingHeroRow: Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let load: String
}

/// The planned session's exercises (by `sessionId`, or by name when the hub carries no id). A
/// missing weight is "—", never an invented load.
public nonisolated func trainingHeroRows(exercises: [Exercise], session: PlannedSession?) -> [TrainingHeroRow] {
    guard let session else { return [] }
    let byId = exercises.filter { $0.sessionId == session.id }
    let picked = byId.isEmpty ? exercises.filter { $0.sessionName == session.name } : byId
    return picked.map { e in
        let kg = e.currentWeightKg.flatMap { $0 > 0 ? String(format: "%.1f kg", $0) : nil }   // 0 kg = bodyweight: no load claimed
        let sets = e.sets.map { "\($0) sets" }
        let load = [kg, sets].compactMap { $0 }.joined(separator: " · ")
        return TrainingHeroRow(id: e.exerciseId, name: e.exerciseName, load: load.isEmpty ? "—" : load)
    }
}

/// B-57 W1 Training header, W-FIX3 fixer BUG-44 (board 3/01): "● Full · Wed 23 Sep" with the
/// synced pill on the same row (stacks at accessibility sizes), then the Watch state.
struct TrainingSessionHeader: View {
    /// W-FIX4 PF-04: `fetchedAt` no longer feeds the pill (the one rule does, `OneSyncedPill`);
    /// kept so `TrainingView`'s call site is unchanged.
    let subtitle: TrainingSubtitle, fetchedAt: Date?, watchLine: String?
    @Environment(\.jiTheme) private var theme
    /// The verdict dot scales with the text and sits on the x-height, not the baseline.
    @ScaledMetric(relativeTo: .subheadline) private var dot: CGFloat = 8
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { subtitleText; Spacer(minLength: 8); OneSyncedPill() }
                VStack(alignment: .leading, spacing: 6) { subtitleText; OneSyncedPill() }
            }
            if let watchLine {
                Label(watchLine, systemImage: "applewatch").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("training-watch-state")
            }
        }
    }

    private var subtitleText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if subtitle.word != nil {
                Circle().fill(trainingToneColor(subtitle.tone, theme)).frame(width: dot, height: dot)
                    .alignmentGuide(.firstTextBaseline) { d in d.height * 1.1 }
                    .accessibilityHidden(true)
            }
            (subtitle.word.map { Text($0).foregroundStyle(trainingToneColor(subtitle.tone, theme)).bold() + Text(" · ") } ?? Text(""))
                + Text(subtitle.dateText)
        }
        .jiFont(.subheadline)
        .foregroundStyle(theme.color(.muted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.text)
        .accessibilityIdentifier("training-date-header")
    }
}

/// W-FIX3 fixer BUG-44 (board 3/01): the hero — "TODAY" + Send to Watch, the session title, its
/// exercise list, and Start session (the live session coach; no separate coach row any more).
struct TrainingHeroCard: View {
    let dayLabel: String, sessionName: String?, rows: [TrainingHeroRow]
    let onSendToWatch: (() -> Void)?, onStart: () -> Void
    @Environment(\.jiTheme) private var theme
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { dayText; Spacer(minLength: 8); watchButton }
                    VStack(alignment: .leading, spacing: 8) { dayText; watchButton }
                }
                Text(sessionName ?? "— \(JIMissingReason.noData.rawValue)")
                    .jiFont(.cardTitleLarge, weight: .bold).foregroundStyle(theme.color(sessionName == nil ? .muted : .text))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("training-session-title")
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline) { rowName(row); Spacer(minLength: 8); rowLoad(row) }
                                VStack(alignment: .leading, spacing: 2) { rowName(row); rowLoad(row) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .accessibilityIdentifier("training-hero-exercises")
                }
                Button(action: onStart) {
                    Text("Start session").jiFont(.statValue, weight: .bold).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.color(.go))
                .accessibilityLabel("Start session")
                .accessibilityHint("Opens the live session coach")
                .accessibilityIdentifier("session-coach-entry")
            }
        }
        .accessibilityIdentifier("training-hero")
    }

    private var dayText: some View {
        Text(dayLabel.uppercased()).jiFont(.footnote, weight: .bold).foregroundStyle(theme.color(.go))
    }

    @ViewBuilder private var watchButton: some View {
        if let onSendToWatch {
            Button(action: onSendToWatch) { Label("Send to Watch", systemImage: "applewatch.radiowaves.left.and.right") }
                .jiFont(.subheadline, weight: .semibold)
                .tint(theme.color(.info))
                .accessibilityLabel("Send to Watch")
                .accessibilityIdentifier("training-send-to-watch")
        }
    }

    private func rowName(_ row: TrainingHeroRow) -> some View {
        Text(row.name).jiFont(.subheadline).foregroundStyle(theme.color(.text))
    }

    private func rowLoad(_ row: TrainingHeroRow) -> some View {
        Text(row.load).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(row.load == "—" ? .muted : .text))
    }
}
