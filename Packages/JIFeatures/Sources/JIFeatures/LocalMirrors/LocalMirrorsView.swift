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
    private let targetsCache: OfflineCache?

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
        targetsCache: OfflineCache? = nil,
        decisionLog: DecisionLogStore?
    ) {
        self.goals = goals
        self.goalStore = goalStore
        self.targets = targets
        self.targetsCache = targetsCache
        self.decisionLog = decisionLog
    }

    public func load() async {
        if goals == nil, let goalStore { goals = try? goalStore.loadGoalTargetsMirror() }
        // W-FIX1 BUG-24: the persisted copy the KPI list writes on every online load — the
        // in-memory list is empty whenever Settings opens without the KPI screen having run.
        if targets.isEmpty, let targetsCache,
           let hit = try? targetsCache.get(localMirrorsKpiTargetsCacheKey, as: [KpiTarget].self) {
            targets = hit.value
        }
        decisions = (try? decisionLog?.recent(limit: Self.recentLimit)) ?? []
    }
}

/// W-FIX1 BUG-24: the `OfflineCache` key `KpiListViewModel` stores `plan.kpi_target` under.
public nonisolated let localMirrorsKpiTargetsCacheKey = "kpi.targets"

// MARK: - B-57 W1 board summary (fixer f3)

/// The board's "Mirrored n of N sets" card. W1 has three mirrored sets on this phone — goal
/// targets, KPI targets, gate decisions (the board's fourth, Challenges, was deleted in W1). A set
/// counts once it holds something; `decisionCount == nil` means the store has not been read yet.
nonisolated public struct LocalMirrorsSummary: Sendable, Equatable {
    public let mirrored: Int
    public let total: Int
    public let word: String
}

public nonisolated func localMirrorsSummary(hasGoals: Bool, targetCount: Int, decisionCount: Int?) -> LocalMirrorsSummary {
    let flags = [hasGoals, targetCount > 0, (decisionCount ?? 0) > 0]
    let mirrored = flags.filter { $0 }.count
    let word = mirrored == 0 ? "Nothing yet" : mirrored == flags.count ? "All mirrored" : "Partial"
    return LocalMirrorsSummary(mirrored: mirrored, total: flags.count, word: word)
}

public struct LocalMirrorsView: View {
    @Environment(\.jiTheme) private var theme
    @State private var model: LocalMirrorsViewModel
    public init(model: LocalMirrorsViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        List {
            let summary = localMirrorsSummary(hasGoals: model.goals != nil, targetCount: model.targets.count,
                                              decisionCount: model.decisions?.count)
            Section {
                BoardSummaryCard(
                    systemImage: "iphone", title: "Mirrored", value: "\(summary.mirrored)", unit: "of \(summary.total) sets",
                    valueTint: summaryRole(summary),
                    status: BoardStatus(word: summary.word,
                                        systemImage: summary.mirrored == summary.total ? "checkmark" : "exclamationmark.triangle",
                                        role: summaryRole(summary)),
                    segments: setFlags.map { $0 ? JIColorRole.go : nil }
                )
                .accessibilityIdentifier("localMirrors.summary")
            }

            // B-57 W1 r4 (g3, board 5/06): the three sets as rows; each set's own list sits one
            // level down. The board's WHEN card (mirror timing) is left for later (spec §2).
            Section {
                NavigationLink {
                    mirrorDetail("Gate decisions") { DecisionLogSection(entries: model.decisions) }
                } label: {
                    setRow("Gate decisions", systemImage: "gauge.with.needle",
                           detail: model.decisions.map { $0.isEmpty ? "No responses yet · on this phone"
                               : "\($0.count) response\($0.count == 1 ? "" : "s") · on this phone" } ?? "Loading…",
                           mirrored: setFlags[2])
                }
                .accessibilityIdentifier("localMirrors.set.decisions")
                NavigationLink {
                    mirrorDetail("KPI targets") {
                        Section { KpiTargetsMirrorSection(targets: model.targets) } header: {
                            Text("KPI targets").accessibilityIdentifier("localMirrors.kpiTargets.header")
                        }
                    }
                } label: {
                    setRow("KPI targets", systemImage: "chart.bar",
                           detail: model.targets.isEmpty ? "Not mirrored yet · next sync at home" : "\(model.targets.count) targets",
                           mirrored: setFlags[1])
                }
                .accessibilityIdentifier("localMirrors.set.kpiTargets")
                NavigationLink {
                    mirrorDetail("Goal targets") {
                        if let goals = model.goals {
                            GoalTargetsMirrorSection(goals: goals)
                        } else {
                            unavailable("Goal targets", "Nothing mirrored yet — open Goals once while online.", id: "goalTargets")
                        }
                    }
                } label: {
                    setRow("Goal targets", systemImage: "target",
                           detail: model.goals == nil ? "Not mirrored yet · next sync at home" : "Current targets",
                           mirrored: setFlags[0])
                }
                .accessibilityIdentifier("localMirrors.set.goalTargets")
            } header: {
                Text("Sets")
            } footer: {
                Text("A set shows Nothing yet until its first sync at home. After that it refreshes with every sync.")
                    .accessibilityIdentifier("localMirrors.info")
            }
        }
        .jiNativeFormChrome()
        .readableColumn()
        .jiTheme(.native)
        .navigationTitle("Local data mirrors")
        .navigationSubtitle("Copies kept on this phone for when you are away from home")
        .task { await model.load() }
    }

    /// goals · KPI targets · gate decisions — whether each set holds anything yet.
    private var setFlags: [Bool] { [model.goals != nil, !model.targets.isEmpty, !(model.decisions ?? []).isEmpty] }

    private func summaryRole(_ s: LocalMirrorsSummary) -> JIColorRole {
        s.mirrored == s.total ? .go : .reduced
    }

    private func setRow(_ title: String, systemImage: String, detail: String, mirrored: Bool) -> some View {
        SettingsLinkLabel(title: title, subtitle: detail, systemImage: systemImage,
                          badge: BoardStatus(word: mirrored ? "Mirrored" : "Nothing yet", systemImage: mirrored ? "checkmark" : "minus",
                                             role: mirrored ? .go : .reduced))
        .accessibilityElement(children: .combine)
    }

    private func mirrorDetail<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        List { content() }
            .jiNativeFormChrome()
            .readableColumn()
            .jiTheme(.native)
            .navigationTitle(title)
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


