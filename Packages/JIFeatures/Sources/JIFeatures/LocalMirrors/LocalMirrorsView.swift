import Foundation
import Observation
import SwiftUI
import JICore
import JIDesign
import JIPersistence

/// W5b-L4 (P-local-mirrors). Oracle: `mobile/app/local-mirrors.tsx` — the four local-first
/// mirror stores as one read-only status screen: what this device has mirrored right now for
/// goals, KPI targets, and gate decisions. Editing each domain stays on its own
/// screen (Goals, KPIs, the gate card on Today); this screen only reads.
///
/// The first two sections are the existing widgets reused verbatim (`GoalTargetsMirrorSection`
/// W4-L3, `KpiTargetsMirrorSection` W3b-L2); the third is this
/// lane's `DecisionLogSection` over `DecisionLogStore`. Rule 5: a domain this device has nothing
/// for renders its own "nothing mirrored yet" line, never an empty card or a zero.
@Observable @MainActor
public final class LocalMirrorsViewModel {
    public private(set) var goals: Goals?
    public private(set) var targets: [KpiTarget]
    /// nil until `load()` has read the store (rule 5 — the section shows "Loading…" meanwhile).
    public private(set) var decisions: [DecisionLogEntry]?

    private let decisionLog: DecisionLogStore?
    private let goalStore: GoalStore?

    /// Oracle `useRecentDecisions(10)` — the section's bounded window.
    public nonisolated static let recentLimit = 10

    /// - goals: the hub document as the Goals screen last loaded/saved it; when nil, `goalStore`'s
    ///   `goal_targets_mirror` copy is read instead (the local-first fallback).
    /// - targets: `plan.kpi_target` rows as the KPI list last fetched them.
    /// - decisionLog: nil = the on-device database could not be opened.
    public init(
        goals: Goals? = nil,
        goalStore: GoalStore? = nil,
        targets: [KpiTarget] = [],
        decisionLog: DecisionLogStore?
    ) {
        self.goals = goals
        self.goalStore = goalStore
        self.targets = targets
        self.decisionLog = decisionLog
    }

    public func load() async {
        if goals == nil, let goalStore { goals = try? goalStore.loadGoalTargetsMirror() }
        decisions = (try? decisionLog?.recent(limit: Self.recentLimit)) ?? []
    }
}

public struct LocalMirrorsView: View {
    @Environment(\.jiTheme) private var theme
    @State private var model: LocalMirrorsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: LocalMirrorsViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        List {
            Section {
                EmptyView()
            } footer: {
                // Oracle `ScreenHeader info=…`, verbatim.
                Text("What this device has mirrored locally for goals, KPI targets, and gate decisions — the hub stays the source of truth until F5d.")
                    .accessibilityIdentifier("localMirrors.info")
            }

            if let goals = model.goals {
                GoalTargetsMirrorSection(goals: goals)
            } else {
                unavailable("Goal targets", "Nothing mirrored yet — open Goals once while online.", id: "goalTargets")
            }

            Section { KpiTargetsMirrorSection(targets: model.targets) }

            DecisionLogSection(entries: model.decisions)

            Section {
                Button("Done") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Done")
                    .accessibilityIdentifier("localMirrors.done")
            }
        }
        .jiNativeFormChrome()
        .readableColumn()
        .jiTheme(.native)
        .navigationTitle("Local data mirrors")
        .task { await model.load() }
    }

    private func unavailable(_ title: String, _ message: String, id: String) -> some View {
        Section {
            Text(message).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .accessibilityIdentifier("localMirrors.\(id).unavailable")
        } header: {
            Text(title)
        }
    }
}


