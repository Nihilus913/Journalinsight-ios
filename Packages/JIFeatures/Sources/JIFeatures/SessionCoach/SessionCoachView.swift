import SwiftUI
import JICore
import JIDesign

/// B-57 W4: the cap copy follows the user's own (optional) cap. nil = no cap, nothing drawn.
public nonisolated func sessionCoachCapTitle(_ s: GateSettings) -> String? { s.hrCapBpm.map { "Your cap \($0)" } }

public nonisolated func sessionCoachCapCaption(_ s: GateSettings) -> String? {
    guard let cap = s.hrCapBpm else { return nil }
    return s.hrCapChosen
        ? "You chose \(cap) in setup. The app never raises it."
        : "\(cap) bpm is from your earlier setup. Confirm or change it in Gate thresholds. The app never raises it."
}

/// The not-available wall's standing rule. nil (row hidden) when the user set no cap and does not
/// avoid Zone 5.
public nonisolated func sessionCoachSafetyLine(_ s: GateSettings) -> String? {
    var parts: [String] = []
    if let cap = s.hrCapBpm { parts.append("HR ≤ \(cap)") }
    if s.zone5FloorBpm != nil, let z = s.zones { parts.append("Zone 5 (\(z.rangeText(5))) avoided") }
    return parts.isEmpty ? nil : "Your limits still apply either way: " + parts.joined(separator: " · ") + "."
}

/// The unit line under the live HR.
public nonisolated func sessionCoachUnitLine(_ s: GateSettings) -> String {
    var parts = ["bpm"]
    if let cap = s.hrCapBpm { parts.append("cap \(cap)") }
    if s.zone5FloorBpm != nil, let z = s.zones { parts.append("Z5 \(z.rangeText(5)) avoided") }
    return parts.joined(separator: " · ")
}

/// The screen's lead line: names a limit only when the user set one.
public nonisolated func sessionCoachIntro(_ s: GateSettings) -> String {
    SessionCoachViewModel.limitBpm(s) == nil
        ? "Live in-session coach — heart rate, time and session load while you train."
        : "Live in-session coach — your heart-rate limit is always the headline, whatever else the session is doing."
}

/// Live Session Coach screen (W3b-L1, P-session-coach). Oracle: `mobile/app/session-coach.tsx` +
/// `mobile/src/components/training/SessionCoach.tsx`. Pushed from Training's `SessionCoachEntry`
/// row — one tap, no tabs of its own (mirrors the RN route's single-screen shell).
public struct SessionCoachView: View {
    @Bindable private var model: SessionCoachViewModel
    /// B-33: `.jiTheme(.native)` installs the theme for descendants, not for the view that
    /// applies it — a screen root's own token reads resolve against this constant.
    private let theme = JITheme.native
    public init(model: SessionCoachViewModel) { self.model = model }

    public var body: some View {
        ScreenScroll {   // W-GUI F6: the shared scroll root (edge effect, sweep branch)
            VStack(alignment: .leading, spacing: 16) {
                Text(sessionCoachIntro(model.settings))
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                if model.capable { capableCard } else { notAvailableCard }
                if let feed = model.mirrored, feed.isMirroring { MirroredSetsCard(feed: feed) }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .jiPageGround()
        .jiGlassBackButton()
        .navigationTitle("Session coach")
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    /// §8.5: the screen's composition without its scrolling root — the sweep renders this
    /// (`ImageRenderer` never lays out a `ScrollView`'s off-screen content).
    @ViewBuilder var nativeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            JISectionHeader("Live session")
            Text(sessionCoachIntro(model.settings))
                .jiFont(.footnote).foregroundStyle(theme.color(.muted))
            if model.capable { capableCard } else { notAvailableCard }
        }
    }

    /// Oracle: `SessionCoach.tsx`'s `NotAvailable()` — an explicit, honest wall, never a hidden
    /// screen and never a fake/frozen reading standing in for a real live source. The safety cap
    /// itself is still stated here — it's a standing rule, not conditional on having a live feed.
    private var notAvailableCard: some View {
        Surface {
            VStack(spacing: 8) {
                Text("LIVE SESSION COACH").jiFont(.micro, weight: .semibold).foregroundStyle(theme.color(.muted))
                Text("No live heart-rate source is connected — this needs a device that streams HR during the workout itself, not a summary synced afterward.")
                    .jiFont(.subheadline).foregroundStyle(theme.color(.text)).multilineTextAlignment(.center)
                if let line = sessionCoachSafetyLine(model.settings) {
                    Text(line).jiFont(.caption).foregroundStyle(theme.color(.muted)).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-coach-unavailable")
    }

    private var capableCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let title = sessionCoachCapTitle(model.settings) {
                        Label(title, systemImage: "info.circle").labelStyle(.titleAndIcon)
                            .jiFont(.micro, weight: .semibold).foregroundStyle(theme.color(.muted))
                            .accessibilityHint(sessionCoachCapCaption(model.settings) ?? "")
                    }
                    Spacer()
                    if model.capState != .noLimit {
                        Text(SessionCoachViewModel.label(for: model.capState))
                            .jiFont(.micro, weight: .heavy)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(trainingToneColor(SessionCoachViewModel.tone(for: model.capState), theme), in: Capsule())
                            .foregroundStyle(Color.white)
                            .accessibilityIdentifier("session-coach-state-badge")
                            .accessibilityLabel("Session state")
                            .accessibilityValue(SessionCoachViewModel.label(for: model.capState))
                    }
                }
                if let caption = sessionCoachCapCaption(model.settings) {
                    Text(caption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("session-coach-cap-caption")
                }
                Text(model.sample?.hrBpm.map(String.init) ?? "—")
                    .jiNumeral(.numeralDisplay, weight: .heavy)
                    .foregroundStyle(trainingToneColor(SessionCoachViewModel.tone(for: model.capState), theme))
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("session-coach-hr")
                    .accessibilityLabel("Heart rate")
                    .accessibilityValue(model.sample?.hrBpm.map { "\($0) bpm" } ?? "No data yet")
                Text(sessionCoachUnitLine(model.settings))
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                Text(SessionCoachViewModel.action(for: model.capState, settings: model.settings))
                    .jiFont(.subheadline).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("session-coach-action")
                if model.sample != nil {
                    Text("Elapsed \(model.elapsedText)").jiFont(.caption).foregroundStyle(theme.color(.muted))
                    loadBar
                } else {
                    Text("Waiting for a live reading…").jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                if let feed = model.mirrored, !feed.isMirroring {
                    // B-8: the Watch session is not running (yet) — say how to start it, not "feed lost".
                    Text(MirroredSessionFeed.FeedError.notMirroring.errorDescription ?? "")
                        .jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("session-coach-start-on-watch")
                } else if let error = model.error {
                    Text("⚠ Live feed lost — reading frozen, not live (\(error))")
                        .jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.reduced))
                        .accessibilityIdentifier("session-coach-stale-banner")
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
    }

    private var loadBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SESSION LOAD").jiFont(.micro, weight: .semibold).foregroundStyle(theme.color(.muted))
                Spacer()
                if let sample = model.sample {
                    Text("\(Int(sample.load.rounded())) / \(Int(sample.targetLoad.rounded()))")
                        .jiFont(.micro).foregroundStyle(theme.color(.muted))
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.color(.nested)).frame(height: 10)
                    Capsule().fill(theme.color(.info)).frame(width: g.size.width * model.loadProgress, height: 10)
                }
            }
            .frame(height: 10)
        }
        .accessibilityIdentifier("session-coach-load")
        .accessibilityLabel("Session load")
        .accessibilityValue(model.sample.map { "\(Int($0.load.rounded())) of \(Int($0.targetLoad.rounded()))" } ?? "No data yet")
    }
}
