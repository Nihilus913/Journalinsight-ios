import Foundation
import Observation
import SwiftUI
import JICore
import JIDesign
import JIPersistence

/// W5b-L4 (P-local-mirrors). Oracle: `mobile/app/local-mirrors.tsx` — the four local-first
/// mirror stores as one read-only status screen: what this device has mirrored right now for
/// goals, KPI targets, challenges, and gate decisions. Editing each domain stays on its own
/// screen (Goals, KPIs, Challenges, the gate card on Today); this screen only reads.
///
/// The first three sections are the existing widgets reused verbatim (`GoalTargetsMirrorSection`
/// W4-L3, `KpiTargetsMirrorSection` W3b-L2, `ChallengesMirrorSection` W3b-L3); the fourth is this
/// lane's `DecisionLogSection` over `DecisionLogStore`. Rule 5: a domain this device has nothing
/// for renders its own "nothing mirrored yet" line, never an empty card or a zero.
@Observable @MainActor
public final class LocalMirrorsViewModel {
    public private(set) var goals: Goals?
    public private(set) var targets: [KpiTarget]
    public let challengesModel: ChallengesViewModel?
    /// nil until `load()` has read the store (rule 5 — the section shows "Loading…" meanwhile).
    public private(set) var decisions: [DecisionLogEntry]?

    private let decisionLog: DecisionLogStore?
    private let goalStore: GoalStore?

    /// Oracle `useRecentDecisions(10)` — the section's bounded window.
    public nonisolated static let recentLimit = 10

    /// - goals: the hub document as the Goals screen last loaded/saved it; when nil, `goalStore`'s
    ///   `goal_targets_mirror` copy is read instead (the local-first fallback).
    /// - targets: `plan.kpi_target` rows as the KPI list last fetched them.
    /// - challengesModel: nil = no hub provider reachable for challenges.
    /// - decisionLog: nil = the on-device database could not be opened.
    public init(
        goals: Goals? = nil,
        goalStore: GoalStore? = nil,
        targets: [KpiTarget] = [],
        challengesModel: ChallengesViewModel? = nil,
        decisionLog: DecisionLogStore?
    ) {
        self.goals = goals
        self.goalStore = goalStore
        self.targets = targets
        self.challengesModel = challengesModel
        self.decisionLog = decisionLog
    }

    public func load() async {
        if goals == nil, let goalStore { goals = try? goalStore.loadGoalTargetsMirror() }
        decisions = (try? decisionLog?.recent(limit: Self.recentLimit)) ?? []
        if let challengesModel, challengesModel.challenges.isEmpty { await challengesModel.load() }
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
                Text("What this device has mirrored locally for goals, KPI targets, challenges, and gate decisions — the hub stays the source of truth until F5d.")
                    .accessibilityIdentifier("localMirrors.info")
            }

            if let goals = model.goals {
                GoalTargetsMirrorSection(goals: goals)
            } else {
                unavailable("Goal targets", "Nothing mirrored yet — open Goals once while online.", id: "goalTargets")
            }

            Section { KpiTargetsMirrorSection(targets: model.targets) }

            if let challengesModel = model.challengesModel {
                ChallengesMirrorSection(model: challengesModel, onEdit: { _ in })
            } else {
                unavailable("Challenges", "Nothing mirrored yet — open Challenges once while online.", id: "challenges")
            }

            DecisionLogSection(entries: model.decisions)

            Section {
                Button("Done") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Done")
                    .accessibilityIdentifier("localMirrors.done")
            }
        }
        .jiNativeFormChrome()
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


