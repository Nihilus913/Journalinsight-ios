import SwiftUI
import JICore
import JIDesign

/// B-57 §2 Day: the morning's result collapsed to one line — "GO · Full Upper · readiness 78".
/// An empty session and a missing readiness are dropped, never rendered as blanks or zeros.
public nonisolated func morningSummaryText(verdict: VerdictParts, readiness: Double?) -> String {
    [verdict.word,
     verdict.session.isEmpty ? nil : verdict.session,
     readiness.map { "readiness \(todayRingValueText($0))" }]
        .compactMap { $0 }
        .joined(separator: " · ")
}

/// B-57 §6/§9: the Day view's top line; tap re-opens the morning's Coach overlay read-only.
/// W-B57b: `verdict` is the effective one (`effectiveVerdictParts`); `caption` is its
/// "was MODIFIED · <reason>" line when the user overrode the verdict.
public struct MorningSummaryLine: View {
    let verdict: VerdictParts
    let readiness: Double?
    let caption: String?
    let onTap: () -> Void
    @Environment(\.jiTheme) private var theme

    public init(verdict: VerdictParts, readiness: Double?, caption: String? = nil, onTap: @escaping () -> Void) {
        self.verdict = verdict; self.readiness = readiness; self.caption = caption; self.onTap = onTap
    }

    private var rest: String {
        let full = morningSummaryText(verdict: verdict, readiness: readiness)
        return String(full.dropFirst(verdict.word.count))
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(verdict.word).foregroundStyle(theme.color(verdictColorRole(verdict.tone)))
                     + Text(rest).foregroundStyle(theme.color(.text)))
                        .jiFont(.footnote, weight: .semibold)
                        .lineLimit(2)
                    if let caption {
                        Text(caption).jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(2)
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
        .accessibilityLabel("This morning: \(morningSummaryText(verdict: verdict, readiness: readiness))\(caption.map { ", \($0)" } ?? ""). Open the morning review")
        .accessibilityIdentifier("today.morning.summary")
    }
}
