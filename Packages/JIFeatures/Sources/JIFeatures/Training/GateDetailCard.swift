import SwiftUI
import JICore
import JIDesign

/// W-FIX4 PF-13: the hub's ISO verdict day as the app writes dates — "Fri 25 Sep" — or "—" when
/// missing or unreadable (never the raw "2026-09-25").
public nonisolated func readinessDateText(_ iso: String?, locale: Locale = .autoupdatingCurrent) -> String {
    guard let iso, iso.count == 10 else { return "—" }
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3,
          let date = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
          utc.component(.day, from: date) == parts[2] else { return "—" }
    let style = Date.FormatStyle(locale: locale, timeZone: utc.timeZone).weekday(.abbreviated).day().month(.abbreviated)
    return date.formatted(style)
}

/// W-FIX11 H1-05: the Readiness card's verdict — the user's call when there is one.
public nonisolated func gateDetailShownParts(verdict: String?, override: VerdictOverride?) -> VerdictParts {
    effectiveVerdictParts(parts: verdictParts(verdict), override: override)
}

/// W-FIX4 PF-13: "Readiness · Fri 25 Sep", or "Readiness from Thu 24 Sep" for a stale verdict.
public nonisolated func gateDetailDateLine(verdictDate: String?, isStale: Bool,
                                           locale: Locale = .autoupdatingCurrent) -> String {
    let day = readinessDateText(verdictDate, locale: locale)
    return isStale ? "Readiness from \(day)" : "Readiness · \(day)"
}

/// Slim readiness summary + gate recommendation (oracle: `GateDetailCard.tsx`). No "gate-rationale"
/// drill-down screen this wave (W3b scope) — the card renders the same two lines without the
/// tap-through chevron/navigation.
public struct GateDetailCard: View {
    let morning: MorningResponse?
    let gate: GateResponse?
    /// B-45 (d): the hub's verdict is whatever day `scripts/morning_go.py` last wrote. When that
    /// is not today, the card says so instead of letting the date read as "now".
    let isStale: Bool
    /// W-FIX11 H1-05: the user's call for the verdict date (nil = none).
    let override: VerdictOverride?
    @Environment(\.jiTheme) private var theme
    public init(morning: MorningResponse?, gate: GateResponse?, isStale: Bool = false, override: VerdictOverride? = nil) {
        self.morning = morning; self.gate = gate; self.isStale = isStale; self.override = override
    }

    /// W-FIX1 BUG-27 (W1 carryover): the user word (Full / Modified / Rest), tinted amber on the
    /// hub's auto-regulated day, never the raw "GO (auto-regulated)". W-FIX11 H1-05: the user's call.
    private var shown: VerdictParts { gateDetailShownParts(verdict: morning?.verdict, override: override) }

    public var body: some View {
        let v = shown
        Surface {
            VStack(alignment: .leading, spacing: 2) {
                Text(gateDetailDateLine(verdictDate: morning?.verdictDate, isStale: isStale))
                    .font(.caption.weight(.semibold)).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("gate-detail-date")
                Text(verdictUserWord(v))
                    .font(.title3.bold())
                    .foregroundStyle(trainingToneColor(v.tone, theme))
                if isStale {
                    Text("No verdict for today yet — this is the last one the hub wrote.")
                        .font(.caption).foregroundStyle(theme.color(.reduced)).padding(.top, 2)
                        .accessibilityIdentifier("gate-detail-stale")
                }
                if override == nil || override?.choice == .accept, let prescription = autoRegulatedPrescription(v) {
                    Text(prescription).font(.footnote).foregroundStyle(theme.color(.text)).padding(.top, 2)
                        .accessibilityIdentifier("gate-detail-prescription")
                }
                if let weekly = gateDetailWeeklyLine(gate) {
                    Text(gateDetailWeeklyCaption(weekly))
                        .font(.footnote).foregroundStyle(theme.color(.muted)).padding(.top, 2)
                }
            }
            // B-46 item 7: `Surface` sizes to its content, so a short card sat narrower than its
            // neighbours. Every card on these screens fills the column instead.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Readiness verdict details")
        .accessibilityValue([verdictUserWord(shown), gateDetailWeeklyLine(gate)].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("gate-detail-card")
    }

}

/// W-FIX11 H1-09: on the Readiness card the weekly note is labelled as the week's nutrition — it
/// never reads as the reason for today's verdict.
public nonisolated func gateDetailWeeklyCaption(_ sentence: String) -> String {
    "Weekly nutrition (not today's call): " + sentence.prefix(1).lowercased() + sentence.dropFirst()
}

/// W-FIX1 BUG-27: the weekly nutrition gate as one plain sentence (never "Gate recommendation:
/// REDUCE"); nil when there is no gate response.
public nonisolated func gateDetailWeeklyLine(_ gate: GateResponse?) -> String? {
    guard let gate else { return nil }
    return weeklyGatePlainSentence(gate.recommendation)
}

/// The weekly nutrition gate's recommendation in the user's words — shared by Training's card and
/// GateRationale's weekly caption.
public nonisolated func weeklyGatePlainSentence(_ recommendation: GateRecommendation) -> String {
    switch recommendation {
    case .progress: "This week's nutrition supports progressing your weights."
    case .maintain: "This week's nutrition says hold your weights where they are."
    case .reduce: "This week's nutrition says ease off — fuel and recovery are short."
    case .insufficientData: "Not enough tracked days this week for a nutrition call."
    }
}
