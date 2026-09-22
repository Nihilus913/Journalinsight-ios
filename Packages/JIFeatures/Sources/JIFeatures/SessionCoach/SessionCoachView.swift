import SwiftUI
import JICore
import JIDesign

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Live in-session coach — the HR-\(SessionCoachViewModel.hrSafetyCapBpm) safety cap is always the headline, whatever else the session is doing.")
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                if model.capable { capableCard } else { notAvailableCard }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(theme.color(.bg))
        .navigationTitle("Session coach")
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    /// §8.5: the screen's composition without its scrolling root — the sweep renders this
    /// (`ImageRenderer` never lays out a `ScrollView`'s off-screen content).
    @ViewBuilder var nativeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            JISectionHeader("Live session")
            Text("Live in-session coach — the HR-\(SessionCoachViewModel.hrSafetyCapBpm) safety cap is always the headline, whatever else the session is doing.")
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
                Text("Safety floor still applies either way: HR ≤ \(SessionCoachViewModel.hrSafetyCapBpm) · Zone 5 (\(SessionCoachViewModel.hrForbiddenZoneLowBpm)-\(SessionCoachViewModel.hrForbiddenZoneHighBpm)) forbidden.")
                    .jiFont(.caption).foregroundStyle(theme.color(.muted)).multilineTextAlignment(.center)
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
                    Text("Live session · HR cap \(SessionCoachViewModel.hrSafetyCapBpm)")
                        .jiFont(.micro, weight: .semibold).foregroundStyle(theme.color(.muted))
                    Spacer()
                    Text(SessionCoachViewModel.label(for: model.capState))
                        .jiFont(.micro, weight: .heavy)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(trainingToneColor(SessionCoachViewModel.tone(for: model.capState), theme), in: Capsule())
                        .foregroundStyle(Color.white)
                        .accessibilityIdentifier("session-coach-state-badge")
                        .accessibilityLabel("Session state")
                        .accessibilityValue(SessionCoachViewModel.label(for: model.capState))
                }
                Text(model.sample?.hrBpm.map(String.init) ?? "—")
                    .jiNumeral(.numeralDisplay, weight: .heavy)
                    .foregroundStyle(trainingToneColor(SessionCoachViewModel.tone(for: model.capState), theme))
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("session-coach-hr")
                    .accessibilityLabel("Heart rate")
                    .accessibilityValue(model.sample?.hrBpm.map { "\($0) bpm" } ?? "No data yet")
                Text("bpm · cap \(SessionCoachViewModel.hrSafetyCapBpm) · Z5 \(SessionCoachViewModel.hrForbiddenZoneLowBpm)-\(SessionCoachViewModel.hrForbiddenZoneHighBpm) forbidden")
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                Text(SessionCoachViewModel.action(for: model.capState))
                    .jiFont(.subheadline).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("session-coach-action")
                if model.sample != nil {
                    Text("Elapsed \(model.elapsedText)").jiFont(.caption).foregroundStyle(theme.color(.muted))
                    loadBar
                } else {
                    Text("Waiting for a live reading…").jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                if let error = model.error {
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
