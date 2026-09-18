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
    /// nil = still loading (rule 5: never a bare empty list while the store is being read).
    let entries: [DecisionLogEntry]?
    public init(entries: [DecisionLogEntry]?) { self.entries = entries }

    /// Oracle `CHOICE_LABEL`, verbatim — keyed on the raw `user_choice` string so an unknown
    /// value still renders as itself.
    public nonisolated static let choiceLabels: [String: String] = ["y": "Generated plan", "N": "Skipped", "override": "Overrode"]

    public var body: some View {
        Surface(level: 2) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("DECISION LOG").font(.caption.bold()).foregroundStyle(JIColor.muted)
                    Spacer()
                    Text("ON THIS DEVICE").font(.caption2.bold()).foregroundStyle(JIColor.muted)
                }
                if let entries {
                    if entries.isEmpty {
                        Text("No gate responses logged yet.").font(.footnote).foregroundStyle(JIColor.muted)
                            .accessibilityIdentifier("localMirrors.decisionLog.empty")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(entries) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Self.choiceLabels[entry.userChoice] ?? entry.userChoice)
                                            .font(.footnote.weight(.semibold)).foregroundStyle(JIColor.text)
                                        Text(Self.timestamp(entry.loggedAt)).font(.caption).foregroundStyle(JIColor.muted)
                                    }
                                    Spacer()
                                    if !entry.synced {
                                        Text("PENDING SYNC").font(.caption2.bold()).foregroundStyle(JIColor.reduced)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(Self.choiceLabels[entry.userChoice] ?? entry.userChoice), \(Self.timestamp(entry.loggedAt))\(entry.synced ? "" : ", pending sync")")
                                .accessibilityIdentifier("localMirrors.decisionLog.row.\(entry.id)")
                            }
                        }
                    }
                } else {
                    Text("Loading…").font(.footnote).foregroundStyle(JIColor.muted)
                }
            }
        }
        .accessibilityIdentifier("localMirrors.decisionLog")
    }

    /// Oracle: `entry.loggedAt.slice(0, 16).replace("T", " ")` — "2026-09-18T07:00".
    public nonisolated static func timestamp(_ loggedAt: String) -> String {
        String(loggedAt.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}
