import SwiftUI
import JICore
import JIDesign
import JICompute

// MARK: - W-DECIDE-HYBRID H-3 / H-4: the Strain card's two states (Toby 2026-10-04)
//
// BEFORE the call: yesterday's strain (0–100, HT `app/vitals/strain.py`) against the user's usual
// range (middle 50 % of loaded days, 120 d). No target.
// AFTER the call (Go or Adjust saved): today's strain so far against "Max today", which follows
// the DECIDED call only — never readiness — so the limit can never disagree with the call.

/// The one table of per-call strain ceilings (scout §3/§4 bands as the start; tune after 4 weeks).
public nonisolated enum DecideStrainCeiling {
    public static let full = 60
    public static let modified = 40
    public static let rest = 20

    /// The ceiling for the decided call. `accept` (Go) takes the hub call's own kind: a green call
    /// = full, an amber one = modified, a rest / red one = rest.
    public static func maxToday(choice: VerdictOverrideChoice, verdict: VerdictParts) -> Int {
        switch choice {
        case .full: return full
        case .modified: return modified
        case .rest: return rest
        case .accept:
            let shown = displayVerdictParts(verdict)
            if TodayMorningFlow.isRestDay(shown) || shown.tone == .red { return rest }
            return shown.tone == .go ? full : modified
        }
    }
}

/// Where a value sits against the usual range.
public nonisolated enum DecideStrainPosition: String, Sendable, Equatable {
    case below = "Below your usual", inside = "Inside your usual", above = "Above your usual"
}

public nonisolated enum DecideStrainState: Equatable, Sendable {
    /// Before the call: yesterday vs the usual range.
    case before(value: Double, usual: ClosedRange<Double>, position: DecideStrainPosition, caption: String)
    /// After the call: today so far vs the call's max.
    case after(value: Double, maxToday: Int, roomLeft: Int, caption: String)
    /// Fewer loaded days than the baseline needs (no numbers yet); `maxToday` once a call exists.
    case calibrating(loadedDays: Int, needed: Int, maxToday: Int?)
    /// The hub sent no strain (older hub / load unreadable).
    case unavailable
}

/// The card's state. `override` must already be the one for the verdict date
/// (`overrideForVerdictDate`); a call exists exactly when it is non-nil (Go writes `accept`).
public nonisolated func decideStrainState(strain: MorningStrain?, override: VerdictOverride?, verdict: VerdictParts,
                                          timeZone: TimeZone = .current) -> DecideStrainState {
    let maxToday = override.map { DecideStrainCeiling.maxToday(choice: $0.choice, verdict: verdict) }
    guard let strain else { return .unavailable }
    if strain.isCalibrating {
        return .calibrating(loadedDays: strain.loadedDays, needed: strain.minLoadedDays, maxToday: maxToday)
    }
    if let override, let maxToday {
        guard let today = strain.today.value else {
            return .calibrating(loadedDays: strain.loadedDays, needed: strain.minLoadedDays, maxToday: maxToday)
        }
        let room = max(0, maxToday - Int(today.rounded()))
        return .after(value: today, maxToday: maxToday, roomLeft: room,
                      caption: decideStrainAfterCaption(choice: override.choice, verdict: verdict, maxToday: maxToday))
    }
    guard let y = strain.yesterday.value, let lo = strain.usualLow, let hi = strain.usualHigh, lo <= hi else {
        return .calibrating(loadedDays: strain.loadedDays, needed: strain.minLoadedDays, maxToday: nil)
    }
    let position: DecideStrainPosition = y < lo ? .below : (y > hi ? .above : .inside)
    return .before(value: y, usual: lo...hi, position: position,
                   caption: decideStrainBeforeCaption(yesterday: strain.yesterday, windowDays: strain.windowDays, timeZone: timeZone))
}

/// "Sun: 48 min Outdoor Run · usual = your middle 50 % of loaded days (120 d)."
public nonisolated func decideStrainBeforeCaption(yesterday: MorningStrain.Day, windowDays: Int, timeZone: TimeZone = .current) -> String {
    let day: String = {
        guard let d = DayKey(iso: yesterday.date)?.startDate(in: .gmt) else { return "Yesterday" }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .gmt
        f.dateFormat = "EEE"
        return f.string(from: d)
    }()
    let sessions = (yesterday.sessions ?? []).map { "\($0.minutes) min \($0.name)" }
    let what = sessions.isEmpty ? "no session" : sessions.joined(separator: " + ")
    return "\(day): \(what) · usual = your middle 50 % of loaded days (\(windowDays) d)."
}

/// "Your call: Go, Strength B → keep today under 60. A limit, not a goal. Modified → 40 · Rest → 20."
public nonisolated func decideStrainAfterCaption(choice: VerdictOverrideChoice, verdict: VerdictParts, maxToday: Int) -> String {
    let others = [("Full", DecideStrainCeiling.full), ("Modified", DecideStrainCeiling.modified), ("Rest", DecideStrainCeiling.rest)]
        .filter { $0.1 != maxToday }
        .map { "\($0.0) → \($0.1)" }
        .joined(separator: " · ")
    let call: String = switch choice {
    case .accept: "Go"
    case .full: "Full session"
    case .modified: "Modified session"
    case .rest: "Rest"
    }
    return "Your call: \(call) → keep today under \(maxToday). A limit, not a goal. \(others)."
}

// MARK: - View

/// The Strain card under Decide's top card (mockup BP-10-11-hybrid, right phone + "two states").
struct DecideStrainCard: View {
    let state: DecideStrainState
    @Environment(\.jiTheme) private var theme

    var body: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Strain").jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                    Text(subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    Spacer(minLength: 0)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.decide.strain")
    }

    private var subtitle: String {
        switch state {
        case .before: "yesterday"
        case .after: "today · after your call"
        case .calibrating(_, _, let max): max == nil ? "yesterday" : "today · after your call"
        case .unavailable: ""
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case let .before(value, usual, position, caption):
            numberRow(value: value, unit: "of 100", right: position.rawValue,
                      sub: "Your usual \(jiNumber(usual.lowerBound, 0))–\(jiNumber(usual.upperBound, 0))")
            DecideStrainBar(value: value, band: usual, marker: nil)
            captionText(caption)
        case let .after(value, maxToday, roomLeft, caption):
            numberRow(value: value, unit: "of 100 so far", right: "Room left: \(roomLeft)", sub: "Max today \(maxToday)")
            DecideStrainBar(value: value, band: nil, marker: Double(maxToday))
            captionText(caption)
        case let .calibrating(loaded, needed, max):
            Text("Calibrating · \(loaded) of \(needed) loaded days").jiFont(.subheadline, weight: .semibold)
                .foregroundStyle(theme.color(.muted))
            if let max { captionText("Max today \(max) — from your call. A limit, not a goal.") }
        case .unavailable:
            Text("— \(JIMissingReason.noData.rawValue)").jiFont(.subheadline, weight: .semibold)
                .foregroundStyle(theme.color(.muted))
        }
    }

    private func numberRow(value: Double, unit: String, right: String, sub: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(jiNumber(value, 0)).jiNumeral(.numeralLarge, weight: .heavy, tint: .text)
                    .accessibilityIdentifier("today.decide.strain.value")
                Text(unit).jiFont(.footnote).foregroundStyle(theme.color(.muted))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(right).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("today.decide.strain.right")
                Text(sub).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("today.decide.strain.range")
            }
        }
    }

    private func captionText(_ text: String) -> some View {
        Text(text).jiFont(.caption).foregroundStyle(theme.color(.muted))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("today.decide.strain.caption")
    }
}

/// 0–100 bar: the usual band shaded (before) or a marker at the max (after); the fill is the value.
/// Never a verdict colour (rule 6): the fill wears the info role, the band the nested fill.
struct DecideStrainBar: View {
    let value: Double
    let band: ClosedRange<Double>?
    let marker: Double?
    @Environment(\.jiTheme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { g in
                let w = g.size.width
                let x: (Double) -> CGFloat = { CGFloat(min(max($0, 0), 100) / 100) * w }
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.color(.nested))
                    if let band {
                        Rectangle().fill(theme.color(.muted).opacity(0.35))
                            .frame(width: max(2, x(band.upperBound) - x(band.lowerBound)))
                            .offset(x: x(band.lowerBound))
                    }
                    Capsule().fill(theme.color(.info)).frame(width: max(4, x(value)))
                    if let marker {
                        Rectangle().fill(theme.color(.text)).frame(width: 2, height: 14)
                            .offset(x: x(marker) - 1)
                    }
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            HStack {
                Text("0")
                Spacer()
                if let band { Text("\(jiNumber(band.lowerBound, 0))–\(jiNumber(band.upperBound, 0))") }
                if let marker { Text("max \(jiNumber(marker, 0))") }
                Spacer()
                Text("100")
            }
            .jiFont(.micro).foregroundStyle(theme.color(.muted))
        }
        .accessibilityHidden(true)
    }
}
