import Foundation
import SwiftUI
import JICore
import JIDesign

/// Screen-level state (DESIGN-7): a strict refinement of `TodayViewModel.Phase`, not a second state
/// machine. `resolve(...)` is a pure function of the same signals `TodayViewModel` already tracks
/// (the phase it already computed, whether any section has ever synced before, the morning verdict's
/// date, and the latest section error) — so `phase` and `screenState` can never disagree about the
/// same fetch, and there is exactly one place (`TodayViewModel.fetchLive`) that decides the outcome.
///
/// Kept as its own type rather than adding cases straight into `Phase`: `Phase` is matched exhaustively
/// by call sites outside this lane's file list, and extending it here — rather than just adding new
/// cases nobody asked those call sites to switch over — would be a breaking, not additive, change this
/// wave. `ScreenState` layers the extra detail on top instead.
nonisolated public enum ScreenState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    /// The hub answered fine and there is genuinely no history — no section has ever synced before
    /// this attempt, and this attempt came back with no verdict and no recovery days. Distinct from
    /// `.empty`, which is a transient blank spell on a screen that has synced successfully before.
    case neverSynced
    /// `morning.verdictDate` is present but isn't today — the hub answered, but the verdict it
    /// returned was computed for an earlier day (a missed or delayed sync). Carries that date for the
    /// banner copy.
    case staleVerdictDate(String)
    /// A section reported `HubError.yazioAuthExpired` — a named UI contract (CLAUDE.md rule 4), always
    /// surfaced regardless of what the other sections did, never flattened into a generic error card.
    case yazioAuthExpired(detail: String)
    case error(String)

    public static func resolve(
        phase: TodayViewModel.Phase,
        neverSynced: Bool,
        verdictDate: String?,
        todayDateString: String,
        lastError: HubError?
    ) -> ScreenState {
        if case .yazioAuthExpired(let detail) = lastError { return .yazioAuthExpired(detail: detail) }
        switch phase {
        case .idle: return .idle
        case .loading: return .loading
        case .error(let message): return .error(message)
        case .empty: return neverSynced ? .neverSynced : .empty
        case .loaded:
            if let verdictDate, verdictDate != todayDateString { return .staleVerdictDate(verdictDate) }
            return .loaded
        }
    }
}

// MARK: - W-GUI-2 X2 (mockups 57–60): the state faces — copy first (pure), then the views

/// The words of the four faces. Every time and count is the caller's (the hub's last call, the
/// nights counted so far); nothing here invents one — a missing time drops out of the sentence.
public nonisolated enum ScreenStateCopy {
    public nonisolated struct Offline: Equatable, Sendable {
        public let pill, line, squares, footer: String
    }
    public nonisolated struct FirstWeek: Equatable, Sendable {
        public let title, subtitle, ring, body, caption: String
        public let nights, needed: Int
    }
    public nonisolated struct Error: Equatable, Sendable {
        public let title, body, hint, retry, testConnection: String
    }
    public nonisolated struct NoSource: Equatable, Sendable {
        public let title, body, action: String
    }

    /// 57: the last call is marked as the last call; the squares carry their "as of" time.
    public static func offline(lastCallAt: String) -> Offline {
        Offline(pill: offlinePillText(lastTime: lastCallAt),
                line: "From \(lastCallAt). The hub is off your network; this is the last call, not a new one.",
                squares: "Your squares · as of \(lastCallAt)",
                footer: "Weigh-ins and check-ins save on the phone and sync later. Nothing is lost by being offline.")
    }

    /// 58: "No call yet · night n of 7" — clamped to 0…needed, never "8 of 7".
    public static func firstWeek(nights: Int, needed: Int = 7) -> FirstWeek {
        let n = min(max(nights, 0), needed)
        return FirstWeek(title: "No call yet", subtitle: "Night \(n) of \(needed)", ring: "\(n) OF \(needed)",
                         body: "Your band needs seven Watch nights. Until then JI shows what it has and decides nothing.",
                         caption: "Nothing here is a verdict. Train as you planned; the first call comes with the seventh night.",
                         nights: n, needed: needed)
    }

    /// 58's signal detail: "4 nights · band forms at 7".
    public static func firstWeekSignalDetail(nights: Int, needed: Int = 7) -> String {
        let n = min(max(nights, 0), needed)
        return "\(n) night\(n == 1 ? "" : "s") · band forms at \(needed)"
    }

    /// 59: the hub failed at `failedAt`; what is kept on the phone is from `keptFrom` (nil = nothing yet).
    public static func error(what: String, failedAt: String?, keptFrom: String?) -> Error {
        let failed = failedAt.map { "The hub answered with an error at \($0)." } ?? "The hub answered with an error."
        let kept = keptFrom.map { "Your last \(what.hasPrefix("the ") ? String(what.dropFirst(4)) : what) from \($0) is still on the phone." }
            ?? "Nothing from an earlier sync is on the phone yet."
        return Error(title: "Couldn't load \(what)", body: "\(failed) \(kept)",
                     hint: "If it keeps failing: Settings › Sync & hub › Test connection.",
                     retry: "Retry", testConnection: "Test connection")
    }

    /// 60: what is missing, where to allow it, when the first value appears.
    public static func noSource(metric: String, needs: String, allow: String, firstValue: String) -> NoSource {
        NoSource(title: "No \(metric) data yet",
                 body: "\(metric.prefix(1).uppercased() + metric.dropFirst()) needs \(needs). \(allow); \(firstValue).",
                 action: "Open Apple Health settings")
    }
}

/// 57: the last call, marked as the last call — the one tinted card of the offline Day.
public struct OfflineCallCard: View {
    let verdictWord: String, session: String, lastCallAt: String, tint: JIColorRole
    @Environment(\.jiTheme) private var theme
    public init(verdictWord: String, session: String, lastCallAt: String, tint: JIColorRole) {
        self.verdictWord = verdictWord; self.session = session; self.lastCallAt = lastCallAt; self.tint = tint
    }
    public var body: some View {
        let copy = ScreenStateCopy.offline(lastCallAt: lastCallAt)
        Surface(padding: JISpacing.cardPadding, tint: theme.color(tint)) {
            JIChevronRow {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(verdictWord).fontWeight(.heavy).foregroundStyle(theme.color(tint)) + Text(" · \(session)").foregroundStyle(theme.color(.text)))
                        .jiFont(.body).fixedSize(horizontal: false, vertical: true)
                    Text(copy.line).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: JISpacing.s2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("state.offline.call")
    }
}

/// 58: one "So far" signal of the first week — the value seen so far and its count, Calibrating.
public nonisolated struct FirstWeekSignal: Identifiable, Sendable, Equatable {
    public let id: String, label: String, value: Double?, unit: String, decimals: Int, detail: String
    public init(id: String, label: String, value: Double?, unit: String, decimals: Int = 0, detail: String) {
        self.id = id; self.label = label; self.value = value; self.unit = unit; self.decimals = decimals; self.detail = detail
    }
}

/// 58: "No call yet · night n of 7" with the progress ring, the signals so far (Calibrating),
/// and "train as you planned". Decides nothing (rule 5 / INVARIANTS 3).
public struct FirstWeekFace: View {
    let nights: Int, needed: Int, signals: [FirstWeekSignal]
    @Environment(\.jiTheme) private var theme
    public init(nights: Int, needed: Int = 7, signals: [FirstWeekSignal] = []) {
        self.nights = nights; self.needed = needed; self.signals = signals
    }
    public var body: some View {
        let copy = ScreenStateCopy.firstWeek(nights: nights, needed: needed)
        VStack(alignment: .leading, spacing: JISpacing.cardGap) {
            Surface(padding: JISpacing.cardPadding, tint: theme.color(.info)) {
                HStack(alignment: .center, spacing: JISpacing.s4) {
                    VStack(alignment: .leading, spacing: JISpacing.s1) {
                        Text(copy.title).jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                        Text(copy.subtitle).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.info))
                        Text(copy.body).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: JISpacing.s2)
                    ZStack {
                        ScoreRing(value: Double(copy.nights), max: Double(copy.needed), tint: theme.color(.info), size: 84)
                        Text(copy.ring).jiFont(.micro, weight: .bold).foregroundStyle(theme.color(.muted))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Night \(copy.nights) of \(copy.needed)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("state.firstweek.hero")
            if !signals.isEmpty {
                JISectionHeader("So far")
                Surface(padding: JISpacing.cardPadding) {
                    VStack(spacing: JISpacing.s2) {
                        ForEach(signals) { s in
                            SignalRow(label: s.label, value: s.value, unit: s.unit, decimals: s.decimals,
                                      status: .missing(.calibrating), detail: s.detail)
                        }
                    }
                }
            }
            Text(copy.caption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("state.firstweek.caption")
        }
    }
}

/// 59: the time, what is kept, Retry (secondary), the path to Test connection (a chevron row).
public struct ErrorFace: View {
    let copy: ScreenStateCopy.Error
    let retry: () -> Void
    let testConnection: (() -> Void)?
    @Environment(\.jiTheme) private var theme
    public init(what: String, failedAt: String?, keptFrom: String?, retry: @escaping () -> Void, testConnection: (() -> Void)? = nil) {
        self.copy = ScreenStateCopy.error(what: what, failedAt: failedAt, keptFrom: keptFrom)
        self.retry = retry; self.testConnection = testConnection
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: JISpacing.cardGap) {
            Surface(padding: JISpacing.cardPadding) {
                VStack(alignment: .leading, spacing: JISpacing.s2) {
                    Text(copy.title).jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                    Text(copy.body).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(copy.retry, action: retry).buttonStyle(.jiSecondary)
                        .accessibilityIdentifier("state.error.retry")
                        .padding(.top, JISpacing.s1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let testConnection {
                Surface(padding: 0) {
                    Button(action: testConnection) {
                        JIChevronRow(title: copy.testConnection, value: "Settings › Sync & hub", systemImage: "antenna.radiowaves.left.and.right")
                            .padding(.horizontal, JISpacing.s4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("state.error.test-connection")
                }
            } else {
                Text(copy.hint).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 60: what is missing, where to allow it, when the first value appears — and the way there.
public struct NoSourceFace: View {
    let copy: ScreenStateCopy.NoSource
    let openSettings: (() -> Void)?
    @Environment(\.jiTheme) private var theme
    public init(copy: ScreenStateCopy.NoSource, openSettings: (() -> Void)? = nil) {
        self.copy = copy; self.openSettings = openSettings
    }
    public var body: some View {
        Surface(padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                Text(copy.title).jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                Text(copy.body).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                if let openSettings {
                    Button(copy.action, action: openSettings).buttonStyle(.jiSecondary)
                        .accessibilityIdentifier("state.nosource.open-settings")
                        .padding(.top, JISpacing.s1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The four gallery faces (§8.5 registry entries "Today offline" / "Today first week" /
/// "Today error" / "Today no source"): fixture times and counts standing in for the hub's — a
/// registry line per face in `Gallery/ScreenRegistry.swift` + a `docs/THEME_STATUS.md` row each.
public enum ScreenStateFaces {
    public nonisolated static let registryNames = ["Today offline", "Today first week", "Today error", "Today no source"]

    public static func offline() -> AnyView {
        AnyView(NativeScreenPreview {
            let copy = ScreenStateCopy.offline(lastCallAt: "07:41")
            ScreenScroll {
                VStack(alignment: .leading, spacing: JISpacing.cardGap) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today").jiFont(.title, weight: .heavy)
                            Text("Friday, September 25").jiFont(.subheadline).foregroundStyle(JITheme.native.color(.muted))
                        }
                        Spacer(minLength: JISpacing.s2)
                        OfflinePill(fetchedAt: Date(timeIntervalSince1970: 1_790_235_660), now: Date(timeIntervalSince1970: 1_790_272_920))
                    }
                    OfflineCallCard(verdictWord: "MODIFIED", session: "Long Zone 2 · ~45 min easy", lastCallAt: "07:41", tint: .reduced)
                    JISectionHeader(copy.squares)
                    HStack(spacing: JISpacing.cardGap) {
                        JITile(family: .square) {
                            VStack(alignment: .leading, spacing: JISpacing.s1) {
                                Text("HRV").jiFont(.caption).foregroundStyle(JITheme.native.color(.muted))
                                Text("20.7").jiNumeral(.numeralCompact, tint: .hrv)
                                Text("Below your normal").jiFont(.caption, weight: .semibold).foregroundStyle(JITheme.native.color(.reduced))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        JITile(family: .square) {
                            VStack(alignment: .leading, spacing: JISpacing.s1) {
                                Text("Resting HR").jiFont(.caption).foregroundStyle(JITheme.native.color(.muted))
                                Text("80").jiNumeral(.numeralCompact, tint: .rhr)
                                Text("In your range").jiFont(.caption, weight: .semibold).foregroundStyle(JITheme.native.color(.go))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text(copy.footer).jiFont(.caption).foregroundStyle(JITheme.native.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(JISpacing.sideMargin)
            }
            .background(JIPageGround())
        })
    }

    public static func firstWeek() -> AnyView {
        AnyView(NativeScreenPreview {
            ScreenScroll {
                FirstWeekFace(nights: 4, signals: [
                    FirstWeekSignal(id: "hrv", label: "Overnight HRV · RMSSD", value: 24.3, unit: "ms", decimals: 1, detail: ScreenStateCopy.firstWeekSignalDetail(nights: 4)),
                    FirstWeekSignal(id: "sleep", label: "Sleep", value: 7.1, unit: "h", decimals: 1, detail: "goal not set · optional"),
                    FirstWeekSignal(id: "rhr", label: "Resting HR", value: 78, unit: "bpm", detail: ScreenStateCopy.firstWeekSignalDetail(nights: 4)),
                ])
                .padding(JISpacing.sideMargin)
            }
            .background(JIPageGround())
        })
    }

    public static func error() -> AnyView {
        AnyView(NativeScreenPreview {
            ScreenScroll {
                ErrorFace(what: "the plan", failedAt: "12:40", keptFrom: "07:41", retry: {}, testConnection: {})
                    .padding(JISpacing.sideMargin)
            }
            .background(JIPageGround())
        })
    }

    public static func noSource() -> AnyView {
        AnyView(NativeScreenPreview {
            ScreenScroll {
                NoSourceFace(copy: ScreenStateCopy.noSource(metric: "energy", needs: "resting and active energy from Apple Health",
                                             allow: "Allow both under Settings › Apple Health",
                                             firstValue: "the first balance appears after 7 clean days"), openSettings: {})
                    .padding(JISpacing.sideMargin)
            }
            .background(JIPageGround())
        })
    }
}
