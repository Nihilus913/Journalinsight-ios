import SwiftUI
import JICore
import JIDesign

/// Energy tab (W3a-L1, frozen contract `EnergyView.init(model:)` for `RootTabView`'s L4 wiring).
/// Composes `EnergyHero` + `IntakeTdeeChart` + `DeficitDayList` from `RecoveryView`'s own
/// loading/error/empty/loaded phase switch (the pattern the wave card names) — single-column only
/// this wave; the RN oracle's >=600dp two-pane layout is left for a follow-up (out of this lane's
/// exit criteria, which cover render-from-fixture + states, not window-size adaptivity).
public struct EnergyView: View {
    @Bindable private var model: EnergyViewModel

    public init(model: EnergyViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(JIColor.muted) }
                case .loaded: loaded
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var header: some View {
        Text("Energy").font(.largeTitle.bold()).foregroundStyle(JIColor.text)
    }

    private var loading: some View {
        Surface(level: 1, radius: JIRadius.hero, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 150); SkeletonBlock(height: 320) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(JIColor.text)
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(JIColor.info)
            }
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let staleDate = staleDateBanner {
                Surface(level: 2) {
                    Text("Showing energy from \(staleDate) — no newer sync yet.").font(.footnote).foregroundStyle(JIColor.muted)
                }
            }
            if let report = model.report {
                EnergyHero(report: report)
                Surface(level: 2, padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DAILY · INTAKE VS TDEE").font(.caption2.bold()).foregroundStyle(JIColor.muted)
                        IntakeTdeeChart(days: report.days)
                    }
                }
            }
            Surface(level: 2, padding: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DAILY LOG").font(.caption2.bold()).foregroundStyle(JIColor.muted)
                    DeficitDayList(days: model.days)
                }
            }
        }
    }

    private var staleDateBanner: String? {
        if case .staleVerdictDate(let date) = model.screenState { return date }
        return nil
    }
}
