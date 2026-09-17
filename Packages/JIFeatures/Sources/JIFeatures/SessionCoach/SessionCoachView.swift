import SwiftUI
import JICore
import JIDesign

/// Live Session Coach screen (W3b-L1, P-session-coach). Oracle: `mobile/app/session-coach.tsx` +
/// `mobile/src/components/training/SessionCoach.tsx`. Pushed from Training's `SessionCoachEntry`
/// row — one tap, no tabs of its own (mirrors the RN route's single-screen shell).
public struct SessionCoachView: View {
    @Bindable private var model: SessionCoachViewModel
    public init(model: SessionCoachViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Live in-session coach — the HR-\(SessionCoachViewModel.hrSafetyCapBpm) safety cap is always the headline, whatever else the session is doing.")
                    .font(.footnote).foregroundStyle(JIColor.muted)
                if model.capable { capableCard } else { notAvailableCard }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
        .navigationTitle("Session coach")
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    /// Oracle: `SessionCoach.tsx`'s `NotAvailable()` — an explicit, honest wall, never a hidden
    /// screen and never a fake/frozen reading standing in for a real live source. The safety cap
    /// itself is still stated here — it's a standing rule, not conditional on having a live feed.
    private var notAvailableCard: some View {
        Surface {
            VStack(spacing: 8) {
                Text("LIVE SESSION COACH").font(.caption2.weight(.semibold)).foregroundStyle(JIColor.muted)
                Text("No live heart-rate source is connected — this needs a device that streams HR during the workout itself, not a summary synced afterward.")
                    .font(.subheadline).foregroundStyle(JIColor.text).multilineTextAlignment(.center)
                Text("Safety floor still applies either way: HR ≤ \(SessionCoachViewModel.hrSafetyCapBpm) · Zone 5 (\(SessionCoachViewModel.hrForbiddenZoneLowBpm)-\(SessionCoachViewModel.hrForbiddenZoneHighBpm)) forbidden.")
                    .font(.caption).foregroundStyle(JIColor.muted).multilineTextAlignment(.center)
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
                        .font(.caption2.weight(.semibold)).foregroundStyle(JIColor.muted)
                    Spacer()
                    Text(SessionCoachViewModel.label(for: model.capState))
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(JIColor.color(for: SessionCoachViewModel.tone(for: model.capState)), in: Capsule())
                        .foregroundStyle(JIColor.bg)
                        .accessibilityIdentifier("session-coach-state-badge")
                }
                Text(model.sample?.hrBpm.map(String.init) ?? "—")
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .foregroundStyle(JIColor.color(for: SessionCoachViewModel.tone(for: model.capState)))
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("session-coach-hr")
                Text("bpm · cap \(SessionCoachViewModel.hrSafetyCapBpm) · Z5 \(SessionCoachViewModel.hrForbiddenZoneLowBpm)-\(SessionCoachViewModel.hrForbiddenZoneHighBpm) forbidden")
                    .font(.footnote).foregroundStyle(JIColor.muted)
                Text(SessionCoachViewModel.action(for: model.capState))
                    .font(.subheadline).foregroundStyle(JIColor.text)
                    .accessibilityIdentifier("session-coach-action")
                if model.sample != nil {
                    Text("Elapsed \(model.elapsedText)").font(.caption).foregroundStyle(JIColor.muted)
                    loadBar
                } else {
                    Text("Waiting for a live reading…").font(.caption).foregroundStyle(JIColor.muted)
                }
                if let error = model.error {
                    Text("⚠ Live feed lost — reading frozen, not live (\(error))")
                        .font(.caption.weight(.semibold)).foregroundStyle(JIColor.reduced)
                        .accessibilityIdentifier("session-coach-stale-banner")
                }
            }
        }
    }

    private var loadBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SESSION LOAD").font(.caption2.weight(.semibold)).foregroundStyle(JIColor.muted)
                Spacer()
                if let sample = model.sample {
                    Text("\(Int(sample.load.rounded())) / \(Int(sample.targetLoad.rounded()))")
                        .font(.caption2).foregroundStyle(JIColor.muted)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(JIColor.mutedNested).frame(height: 10)
                    Capsule().fill(JIColor.muted).frame(width: g.size.width * model.loadProgress, height: 10)
                }
            }
            .frame(height: 10)
        }
    }
}
