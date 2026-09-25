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

/// B-57 §6/§9: the Day view's top line; tap re-opens the morning's Coach overlay read-only.
/// W-B57b: `verdict` is the effective one (`effectiveVerdictParts`); `caption` is its
/// "was MODIFIED · <reason>" line when the user overrode the verdict.
public struct MorningSummaryLine: View {
    let verdict: VerdictParts
    let readiness: Double?
    let caption: String?
    let override: VerdictOverride?
    let onTap: () -> Void
    @Environment(\.jiTheme) private var theme

    public init(verdict: VerdictParts, readiness: Double?, caption: String? = nil, override: VerdictOverride? = nil,
                onTap: @escaping () -> Void) {
        self.verdict = verdict; self.readiness = readiness; self.caption = caption; self.override = override; self.onTap = onTap
    }

    private var line: String { dayTitleLine(verdict: verdict, override: override, readiness: readiness) }
    private var rest: String { String(line.dropFirst(verdictUserWord(verdict).count)) }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    // W-FIX3 BUG-33: wraps whole at AX3 — no line limit, never "Day 3 Full Upper +…".
                    (Text(verdictUserWord(verdict)).foregroundStyle(theme.color(verdictColorRole(verdict.tone)))
                     + Text(rest).foregroundStyle(theme.color(.text)))
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
