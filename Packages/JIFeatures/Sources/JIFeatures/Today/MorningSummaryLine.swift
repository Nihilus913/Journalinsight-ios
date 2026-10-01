import SwiftUI
import JICore
import JIDesign

/// B-57 §2 Day: the morning's result collapsed to one line — "Full · Full Upper · readiness 78".
/// An empty session and a missing readiness are dropped, never rendered as blanks or zeros.
/// W-FIX1 BUG-27: the lead is the user word (`verdictUserWord`: Full / Modified / Rest), never the
/// hub's "GO (auto-regulated)".
public nonisolated func morningSummaryText(verdict: VerdictParts, readiness: Double?) -> String {
    [verdictUserWord(verdict),
     verdict.session.isEmpty ? nil : verdict.session,
     readiness.map { "readiness \(todayRingValueText($0))" }]
        .compactMap { $0 }
        .joined(separator: " · ")
}

/// W-FIX3 BUG-28 (board 02): the Day title line — "Full · Day 2 Full Upper · you said Go 08:02".
/// The last part is the user's own call and when it was made (Go = "you said Go", a different call
/// = "you picked Rest"); before any call it is the readiness, as before. A call with no time yet
/// (queued, not confirmed by the hub) shows without one — never an invented time.
public nonisolated func dayTitleLine(verdict: VerdictParts, override: VerdictOverride?, readiness: Double?,
                                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
    let base = morningSummaryText(verdict: verdict, readiness: override == nil ? readiness : nil)
    guard let override else { return base }
    let said: String
    switch override.choice {
    case .accept: said = "you said Go"
    case .full: said = "you picked Full"
    case .modified: said = "you picked Modified"
    case .rest: said = "you picked Rest"
    }
    let time = parseHubTimestamp(override.createdAt).map { date -> String in
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    return [base, [said, time].compactMap { $0 }.joined(separator: " ")].joined(separator: " · ")
}

/// W-FIX9 C-1: the Day title line with its tinted lead word.
public nonisolated struct DayTitleText: Equatable, Sendable {
    public let word: String
    public let tone: VerdictTone
    /// Everything after the word, including its leading separator.
    public let rest: String
    public var line: String { word + rest }
}

/// W-FIX9 C-1 (B-83): once today's planned session is matched by a registered workout — the ONE
/// rule, `SessionCompletion.progress`, that also drives NEXT's "Done ·" line — the line leads with
/// **Completed** (status green) instead of the morning call: "Completed · Day 1 Full Upper ·
/// Traditional strength · 22 min · Bevel 20:16". One part of two done = "Completed strength · Z2
/// open · …". A rest day or no match leaves the line exactly as `dayTitleLine` has it.
public nonisolated func dayTitle(verdict: VerdictParts, override: VerdictOverride?, readiness: Double?,
                                 progress: SessionProgress? = nil, session: String? = nil,
                                 timeZone: TimeZone = .autoupdatingCurrent) -> DayTitleText {
    let word = verdictUserWord(verdict)
    let base = dayTitleLine(verdict: verdict, override: override, readiness: readiness, timeZone: timeZone)
    guard let progress, progress.isComplete || progress.isPartial, let lead = progress.lead else {
        return DayTitleText(word: word, tone: verdict.tone, rest: String(base.dropFirst(word.count)))
    }
    let workout = completedWorkoutLine(lead, timeZone: timeZone)
    let head: String
    if progress.isComplete {
        head = [session.flatMap { $0.isEmpty ? nil : $0 }, workout].compactMap { $0 }.map { " · \($0)" }.joined()
    } else {
        let done = progress.doneParts.map(\.shortName).joined(separator: " + ")
        let open = progress.openParts.map(\.shortName).joined(separator: " + ")
        head = " \(done) · \(open) open · \(workout)"
    }
    return DayTitleText(word: "Completed", tone: .go, rest: head)
}

/// "Traditional strength · 22 min · Bevel 20:16" — the source with the time it ended (no source:
/// just the time).
public nonisolated func completedWorkoutLine(_ w: TodayWorkout, timeZone: TimeZone = .autoupdatingCurrent) -> String {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
    let c = cal.dateComponents([.hour, .minute], from: w.end)
    let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    let source = [w.sourceName.flatMap { $0.isEmpty ? nil : $0 }, time].compactMap { $0 }.joined(separator: " ")
    return [w.activityName, "\(w.durationMinutes) min", source].joined(separator: " · ")
}

/// B-57 §6/§9: the Day view's top line; tap re-opens the morning's Coach overlay read-only.
/// W-B57b: `verdict` is the effective one (`effectiveVerdictParts`); `caption` is its
/// "was MODIFIED · <reason>" line when the user overrode the verdict.
public struct MorningSummaryLine: View {
    let verdict: VerdictParts
    let readiness: Double?
    let caption: String?
    let override: VerdictOverride?
    /// W-FIX9 C-1: today's session against today's workouts (nil = not known → the call as before).
    let progress: SessionProgress?
    let session: String?
    let onTap: () -> Void
    @Environment(\.jiTheme) private var theme

    public init(verdict: VerdictParts, readiness: Double?, caption: String? = nil, override: VerdictOverride? = nil,
                progress: SessionProgress? = nil, session: String? = nil, onTap: @escaping () -> Void) {
        self.verdict = verdict; self.readiness = readiness; self.caption = caption; self.override = override
        self.progress = progress; self.session = session; self.onTap = onTap
    }

    private var title: DayTitleText {
        dayTitle(verdict: verdict, override: override, readiness: readiness, progress: progress, session: session)
    }
    private var line: String { title.line }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    // W-FIX3 BUG-33: wraps whole at AX3 — no line limit, never "Day 3 Full Upper +…".
                    (Text(title.word).foregroundStyle(theme.color(verdictColorRole(title.tone)))
                     + Text(title.rest).foregroundStyle(theme.color(.text)))
                        .jiFont(.subheadline, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(theme.color(.muted))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel("This morning: \(line)\(caption.map { ", \($0)" } ?? ""). Open the morning review")
        .accessibilityIdentifier("today.morning.summary")
    }
}
