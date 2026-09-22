import SwiftUI
import JIDesign
import JIPersistence

/// Oracle: `mobile/src/components/decisions/DecisionLogSection.tsx` — the read-only view of
/// `DecisionLogStore`'s `decision_log_mirror` for `LocalMirrorsView`. Unlike its three siblings
/// this domain has NO hub GET to mirror from (see `DecisionLogStore.swift`'s header) — every row
/// shown here was written locally the moment the user answered the gate, so there is no
/// "hub"/"mirror" source badge: it always reads the same local table, online or offline.
/// `synced == false` rows (the hub POST hasn't confirmed yet) are called out individually instead.
public struct DecisionLogSection: View {
    @Environment(\.jiTheme) private var theme
    /// nil = still loading (rule 5: never a bare empty list while the store is being read).
    let entries: [DecisionLogEntry]?
    public init(entries: [DecisionLogEntry]?) { self.entries = entries }

    /// Oracle `CHOICE_LABEL`, verbatim — keyed on the raw `user_choice` string so an unknown
    /// value still renders as itself.
    public nonisolated static let choiceLabels: [String: String] = ["y": "Generated plan", "N": "Skipped", "override": "Overrode"]

    /// §2b.2: a real `List` section — system header, 44-pt rows, no drawn card.
    public var body: some View {
        Section {
            if let entries {
                if entries.isEmpty {
                    Text("No gate responses logged yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("localMirrors.decisionLog.empty")
                } else {
                    ForEach(entries) { entry in
                        JIRow(title: Self.choiceLabels[entry.userChoice] ?? entry.userChoice,
                              subtitle: Self.timestamp(entry.loggedAt)) {
                            if !entry.synced {
                                Text("Pending sync").jiFont(.micro, weight: .bold).foregroundStyle(theme.color(.reduced))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(Self.choiceLabels[entry.userChoice] ?? entry.userChoice), \(Self.timestamp(entry.loggedAt))\(entry.synced ? "" : ", pending sync")")
                        .accessibilityIdentifier("localMirrors.decisionLog.row.\(entry.id)")
                    }
                }
            } else {
                Text("Loading…").jiFont(.footnote).foregroundStyle(theme.color(.muted))
            }
        } header: {
            Text("Decision log")
        } footer: {
            Text("On this device")
        }
        .accessibilityIdentifier("localMirrors.decisionLog")
    }

    /// Oracle: `entry.loggedAt.slice(0, 16).replace("T", " ")` — "2026-09-18T07:00".
    public nonisolated static func timestamp(_ loggedAt: String) -> String {
        String(loggedAt.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}
