import Foundation
import Observation
import SwiftUI
import JICore
import JIDesign
import JIPersistence

/// W5b-L4 (P-gate-respond). Oracle: `mobile/src/components/GateRespondCard.tsx` +
/// `mobile/src/components/SessionFeelInput.tsx` (both mounted inside RN's `VerdictHero.tsx`, which
/// is why the feel row lives in this file rather than a screen of its own).
///
/// Offline-first, in the exact order the W5b card pins: the answer is enqueued on the `Outbox`
/// FIRST (so it survives the app going offline or being killed mid-request), THEN posted, and only
/// a confirmed POST writes the `decision_log_mirror` row and attaches the hub's `log_id`. A
/// network failure leaves the outbox row pending; any other hub rejection bumps `attempts` and
/// records the hub's own `detail` verbatim.
@Observable @MainActor
public final class GateRespondViewModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case submitting
        /// The hub confirmed and the mirror row is written.
        case logged
        /// Enqueued but not confirmed (hub unreachable) — it stays in the outbox for a later
        /// retry; not a failure the user has to act on.
        case queued
        case failed(String)
    }

    /// The recommendation the user is actually answering — `INSUFFICIENT_DATA` hides the card
    /// entirely (oracle: the early `return null`).
    public let recommendation: GateRecommendation
    public let windowDays: Int

    public private(set) var phase: Phase = .idle
    public private(set) var choice: GateChoice?
    /// `GateRespondOut.pdf_requested` from the last confirmed answer.
    public private(set) var pdfRequested = false

    public private(set) var feelPhase: Phase = .idle
    public private(set) var feelScore: Int?

    private let provider: any GateRespondProviding
    private let outbox: Outbox
    private let decisionLog: DecisionLogStore
    private let now: @Sendable () -> Date

    public nonisolated static let gateRespondKind = "gateRespond"
    public nonisolated static let sessionFeelKind = "sessionFeel"

    public init(
        recommendation: GateRecommendation,
        windowDays: Int = 7,
        provider: any GateRespondProviding,
        outbox: Outbox,
        decisionLog: DecisionLogStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.recommendation = recommendation
        self.windowDays = windowDays
        self.provider = provider
        self.outbox = outbox
        self.decisionLog = decisionLog
        self.now = now
    }

    /// Oracle `useGateRespondStatus`'s `responded`: a choice that settled without an error. A
    /// queued (offline) answer counts as answered — RN's local-first wrapper resolves it too.
    public var responded: Bool { choice != nil && (phase == .logged || phase == .queued) }

    public var errorMessage: String? { if case .failed(let message) = phase { message } else { nil } }
    public var feelErrorMessage: String? { if case .failed(let message) = feelPhase { message } else { nil } }

    /// `POST /api/v1/planning/gate/respond` (HT `app/planning/router.py:325`).
    @discardableResult
    public func respond(choice: GateChoice, overrideReason: String = "") async -> Bool {
        phase = .submitting
        self.choice = choice
        let body = GateRespondBody(choice: choice, overrideReason: overrideReason, windowDays: windowDays)
        let queuedId: Int64
        do {
            queuedId = try outbox.enqueue(kind: Self.gateRespondKind, payload: body, now: now())
        } catch {
            self.choice = nil
            phase = .failed("Couldn't save your answer — try again.")
            return false
        }
        do {
            let result = try await provider.respondGate(choice: choice, overrideReason: overrideReason, windowDays: windowDays)
            try? outbox.markSent(id: queuedId)
            writeMirrorRow(choice: choice, overrideReason: overrideReason, remoteLogId: result.logId)
            pdfRequested = result.pdfRequested
            phase = .logged
            return true
        } catch {
            try? outbox.markFailed(id: queuedId, error: Self.describe(error))
            if case HubError.network = error {
                phase = .queued
                return true
            }
            self.choice = nil
            phase = .failed(Self.describe(error))
            return false
        }
    }

    /// `POST /api/v1/planning/feel` (HT `app/planning/router.py:360`) — same outbox-first order.
    @discardableResult
    public func logFeel(score: Int, notes: String = "", date: String? = nil) async -> Bool {
        feelPhase = .submitting
        feelScore = score
        let body = FeelBody(feelScore: score, notes: notes, date: date)
        let queuedId: Int64
        do {
            queuedId = try outbox.enqueue(kind: Self.sessionFeelKind, payload: body, now: now())
        } catch {
            feelScore = nil
            feelPhase = .failed("Couldn't save that score — try again.")
            return false
        }
        do {
            _ = try await provider.logFeel(feelScore: score, notes: notes, date: date)
            try? outbox.markSent(id: queuedId)
            feelPhase = .logged
            return true
        } catch {
            try? outbox.markFailed(id: queuedId, error: Self.describe(error))
            if case HubError.network = error {
                feelPhase = .queued
                return true
            }
            feelScore = nil
            feelPhase = .failed(Self.describe(error))
            return false
        }
    }

    /// Oracle `confirmUndo`: local-only state, never a server call — there is no hub GET for
    /// "what did I already answer today", so clearing it simply re-shows the buttons. The gate
    /// recommendation itself is untouched, and the `decision_log_mirror` row already written
    /// stays (it records what the user actually did).
    public func undo() {
        choice = nil
        pdfRequested = false
        phase = .idle
    }

    /// Append-then-mark, so the store's two-step contract (and its PENDING SYNC state) is the one
    /// the UI reads back, not a shortcut insert.
    private func writeMirrorRow(choice: GateChoice, overrideReason: String, remoteLogId: Int?) {
        let entry = NewDecisionLogEntry(
            loggedAt: now().ISO8601Format(),
            windowDays: windowDays,
            recommendation: recommendation.rawValue,
            userChoice: choice.rawValue,
            overrideReason: overrideReason.isEmpty ? nil : overrideReason
        )
        guard let localId = try? decisionLog.append(entry) else { return }
        try? decisionLog.markSynced(localId: localId, remoteLogId: remoteLogId)
    }

    /// The hub's own `detail` verbatim for a named `HubError` that carries one (a 502 decodes as
    /// `.yazioAuthExpired` whichever endpoint raised it — see `HubError.from`); a generic retry
    /// line otherwise. Same convention as `OutboxDrainer.describe`.
    public nonisolated static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .yazioAuthExpired(let detail) where !detail.isEmpty: detail
        case .duplicate(let detail) where !detail.isEmpty: detail
        case .http(_, let detail) where detail?.isEmpty == false: detail!
        case .network(let message): message
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        default: "Couldn't log your answer — try again."
        }
    }
}

/// Oracle `GateRespondCard.tsx`'s `CHOICE_LABEL` / `OVERRIDE_REASONS`, verbatim.
public nonisolated enum GateRespondCopy {
    public static let choiceLabels: [GateChoice: String] = [
        .yes: "generate plan", .skip: "skip", .override: "override & generate",
    ]
    public static let overrideReasons = [
        "Feel good despite metrics",
        "Experiment protocol",
        "Schedule constraint",
        "Clinician guidance",
        "Other…",
    ]
    public static let otherReason = "Other…"
    /// Oracle `UNDO_CONFIRM_WINDOW_MS` — the first Undo tap only ARMS the confirm, so a stray tap
    /// can never silently erase a logged response.
    public static let undoConfirmWindow: Duration = .milliseconds(3000)
}

/// The respond controls under the verdict (mounted by `VerdictHeroView`). Asymmetric
/// confirm-on-reversal, exactly like the oracle: answering stays one frictionless tap, undoing it
/// costs a second confirming tap.
public struct GateRespondCard: View {
    @Bindable var model: GateRespondViewModel
    /// B-42: `false` when the card is presented from `VerdictHeroView`'s sheet, whose own compact
    /// action row already carries the 1–5 feel controls — two live copies of `today.feel.N` on
    /// screen at once would make the identifier ambiguous for the sim smoke and for VoiceOver.
    let showsFeelRow: Bool
    @Environment(\.jiTheme) private var theme
    @State private var reasonChoice: String?
    @State private var otherText = ""

    public init(model: GateRespondViewModel, showsFeelRow: Bool = true) {
        self.model = model; self.showsFeelRow = showsFeelRow
    }

    private var overrideReason: String {
        reasonChoice == GateRespondCopy.otherReason ? otherText.trimmingCharacters(in: .whitespacesAndNewlines) : (reasonChoice ?? "")
    }
    private var overrideReady: Bool { reasonChoice != nil && !overrideReason.isEmpty }
    private var busy: Bool { model.phase == .submitting }

    public var body: some View {
        // Oracle: `if (gate.recommendation === "INSUFFICIENT_DATA") return null`.
        if model.recommendation == .insufficientData {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.color(.hairlineNested))
                Text("RESPOND TO THIS RECOMMENDATION")
                    .font(.caption2.weight(.semibold)).foregroundStyle(theme.color(.muted))

                if model.responded {
                    GateRespondedRow(model: model)
                } else if model.recommendation == .reduce {
                    overrideControls
                } else {
                    plainControls
                }

                if let message = model.errorMessage {
                    Text("\(message) — try again.").font(.caption).foregroundStyle(theme.color(.danger))
                        .accessibilityIdentifier("today.gateRespond.error")
                }

                if showsFeelRow { SessionFeelRow(model: model) }
            }
            .padding(.top, 14)
            // Oracle: `hapticSaveSuccess()` once the response actually saved (false → true edge).
            .jiHaptic(.success, trigger: model.responded)
        }
    }
    @ViewBuilder private var plainControls: some View {
        HStack(spacing: 10) {
            Button("Yes") { Task { await model.respond(choice: .yes) } }
                .buttonStyle(.pressableScale)
                .disabled(busy)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(theme.color(.info), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                .foregroundStyle(theme.color(.bg)).font(.footnote.bold())
                .accessibilityLabel("Yes, generate plan")
                .accessibilityIdentifier("today.gateRespond.yes")
            skipButton
        }
    }

    @ViewBuilder private var overrideControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Override reason").font(.caption.weight(.semibold)).foregroundStyle(theme.color(.muted))
            // A wrapping row of chips; `FlowLayout` isn't in JIDesign, so a simple VStack of
            // HStacks would fix the column count — a ViewThatFits-free `LazyVGrid` keeps it fluid.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(GateRespondCopy.overrideReasons, id: \.self) { reason in
                    let selected = reasonChoice == reason
                    Button(reason) { reasonChoice = reason }
                        .buttonStyle(.pressableScale)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(selected ? theme.color(.reduced) : theme.color(.text))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? theme.color(.reduced).opacity(0.18) : theme.color(.control), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                        .overlay(RoundedRectangle(cornerRadius: theme.radius(.control)).stroke(selected ? theme.color(.reduced) : .clear))
                        .accessibilityLabel(reason)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityIdentifier("today.gateRespond.reason.\(reason)")
                }
            }
            if reasonChoice == GateRespondCopy.otherReason {
                TextField("Say why (required)", text: $otherText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(theme.color(.control), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                    .foregroundStyle(theme.color(.text)).font(.footnote)
                    .accessibilityLabel("Override reason, free text")
                    .accessibilityIdentifier("today.gateRespond.reasonText")
            }
            HStack(spacing: 10) {
                Button("Override & generate") {
                    Task { await model.respond(choice: .override, overrideReason: overrideReason) }
                }
                .buttonStyle(.pressableScale)
                .disabled(busy || !overrideReady)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(theme.color(.reduced), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                .foregroundStyle(theme.color(.bg)).font(.footnote.bold())
                .accessibilityLabel("Override and generate plan")
                .accessibilityIdentifier("today.gateRespond.override")
                skipButton
            }
        }
    }

    @ViewBuilder private var skipButton: some View {
        Button("Skip") { Task { await model.respond(choice: .skip) } }
            .buttonStyle(.pressableScale)
            .disabled(busy)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(theme.color(.control), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
            .foregroundStyle(theme.color(.text)).font(.footnote.weight(.semibold))
            .accessibilityLabel("Skip")
            .accessibilityIdentifier("today.gateRespond.skip")
    }

}

/// B-42: the one-liner a answered recommendation collapses to — its own view so both the card and
/// `VerdictHeroView`'s compact action row show the same row (and the same asymmetric
/// confirm-on-reversal Undo) without either owning the other's state.
public struct GateRespondedRow: View {
    @Bindable var model: GateRespondViewModel
    @Environment(\.jiTheme) private var theme
    @State private var undoArmed = false
    @State private var disarmTask: Task<Void, Never>?

    public init(model: GateRespondViewModel) { self.model = model }

    public var body: some View {
        HStack {
            Text("Logged: \(GateRespondCopy.choiceLabels[model.choice ?? .yes] ?? "")")
                .font(.footnote.bold()).foregroundStyle(theme.color(.info))
                .accessibilityIdentifier("today.gateRespond.logged")
            if model.phase == .queued {
                Text("PENDING SYNC").font(.caption2.bold()).foregroundStyle(theme.color(.reduced))
                    .accessibilityIdentifier("today.gateRespond.pending")
            }
            Spacer()
            if undoArmed {
                HStack(spacing: 10) {
                    Button("Undo?") { confirmUndo() }
                        .font(.caption.bold()).foregroundStyle(theme.color(.reduced))
                        .buttonStyle(.pressableScale)
                        .accessibilityLabel("Confirm undo")
                        .accessibilityIdentifier("today.gateRespond.undoConfirm")
                    Button("Keep") { cancelUndo() }
                        .font(.caption.weight(.semibold)).foregroundStyle(theme.color(.muted))
                        .buttonStyle(.pressableScale)
                        .accessibilityLabel("Keep this response")
                        .accessibilityIdentifier("today.gateRespond.undoKeep")
                }
            } else {
                Button("Undo") { armUndo() }
                    .font(.caption.weight(.semibold)).foregroundStyle(theme.color(.muted))
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Undo this response")
                    .accessibilityIdentifier("today.gateRespond.undo")
            }
        }
        .jiHapticCue(.selection, trigger: undoArmed)   // W8-L1 (P-haptics) — oracle GateRespondCard.tsx:95 armUndo() → hapticSelection()
    }

    private func armUndo() {
        undoArmed = true
        disarmTask?.cancel()
        disarmTask = Task {
            try? await Task.sleep(for: GateRespondCopy.undoConfirmWindow)
            guard !Task.isCancelled else { return }
            undoArmed = false
        }
    }
    private func cancelUndo() {
        disarmTask?.cancel()
        undoArmed = false
    }
    private func confirmUndo() {
        disarmTask?.cancel()
        undoArmed = false
        model.undo()
    }
}

/// Oracle `SessionFeelInput.tsx` — the 1–5 row RN mounts in the same `VerdictHero`.
struct SessionFeelRow: View {
    @Bindable var model: GateRespondViewModel
    @Environment(\.jiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW DID IT FEEL?").font(.caption2.weight(.semibold)).foregroundStyle(theme.color(.muted))
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { score in
                    let selected = model.feelScore == score
                    Button("\(score)") { Task { await model.logFeel(score: score) } }
                        .buttonStyle(.pressableScale)
                        .disabled(model.feelPhase == .submitting)
                        .frame(width: 30, height: 30)
                        .background(selected ? theme.color(.info) : theme.color(.surface2), in: Circle())
                        .foregroundStyle(selected ? theme.color(.bg) : theme.color(.text))
                        .font(.caption.bold())
                        .accessibilityLabel("Feel \(score)")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityIdentifier("today.feel.\(score)")
                }
            }
            if let score = model.feelScore, model.feelPhase == .logged || model.feelPhase == .queued {
                Text("Logged \(score)/5").font(.caption).foregroundStyle(theme.color(.info))
                    .accessibilityIdentifier("today.feel.logged")
            }
            if let message = model.feelErrorMessage {
                Text("\(message) — try again.").font(.caption).foregroundStyle(theme.color(.danger))
                    .accessibilityIdentifier("today.feel.error")
            }
        }
        .padding(.top, 10)
    }
}
