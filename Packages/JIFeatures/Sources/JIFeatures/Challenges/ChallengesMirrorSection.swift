import SwiftUI
import JICore
import JIDesign

/// The Active/Past challenge list (oracle: `app/challenges.tsx`'s two `.map` blocks over
/// `ChallengeCard`). Named to match the RN component family (`ChallengesMirrorSection.tsx`) that
/// this screen's list rendering corresponds to; unlike the oracle's read-only local-first mirror
/// widget, this is the full CRUD screen's own list (no separate offline-mirror store this lane —
/// not in L3's `consumes`), so "mirror" here means "renders the current `ChallengesViewModel`
/// rows," not a second local cache.
public struct ChallengesMirrorSection: View {
    @Bindable var model: ChallengesViewModel
    let onEdit: (GateChallenge) -> Void

    public init(model: ChallengesViewModel, onEdit: @escaping (GateChallenge) -> Void) {
        self.model = model; self.onEdit = onEdit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVE").font(.caption.bold()).foregroundStyle(JIColor.muted)
                if model.active.isEmpty {
                    Text("No active challenge right now.").font(.footnote).foregroundStyle(JIColor.muted)
                } else {
                    ForEach(model.active) { challenge in
                        ChallengeCard(challenge: challenge, model: model, onEdit: { onEdit(challenge) })
                    }
                }
            }
            if !model.past.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PAST").font(.caption.bold()).foregroundStyle(JIColor.muted)
                    ForEach(model.past) { challenge in
                        ChallengeCard(challenge: challenge, model: model, onEdit: { onEdit(challenge) })
                    }
                }
            }
        }
    }
}

/// One challenge row (oracle: `ChallengeCard`). Owns its own archive/delete confirm dialogs and
/// menu-expand state — the list above stays a pure `ForEach` over `ChallengesViewModel.challenges`.
struct ChallengeCard: View {
    let challenge: GateChallenge
    @Bindable var model: ChallengesViewModel
    let onEdit: () -> Void

    @State private var menuOpen = false
    @State private var dialog: DialogKind?
    @State private var completeNote = ""
    @State private var actionError: String?
    @State private var isBusy = false

    private enum DialogKind: Identifiable { case complete, archive, delete
        var id: Self { self }
    }

    private static let statusLabel: [ChallengeStatus: String] = [.active: "Active", .completed: "Completed", .archived: "Archived"]

    var body: some View {
        Surface(level: 2, padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(challenge.title).font(.subheadline.bold()).foregroundStyle(JIColor.text)
                    Spacer()
                    Text(Self.statusLabel[challenge.status] ?? "")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(challenge.status == .active ? JIColor.reduced : JIColor.surface3, in: Capsule())
                        .foregroundStyle(challenge.status == .active ? JIColor.bg : JIColor.text)
                    Button { menuOpen.toggle() } label: { Image(systemName: "ellipsis.circle") }
                        .buttonStyle(.pressableScale)
                        .accessibilityLabel("\(challenge.title) actions")
                }
                Text(challenge.hypothesis).font(.footnote).foregroundStyle(JIColor.muted).lineLimit(3)
                Text("Started \(challenge.startDate) · \(challenge.sessionFilter) sessions")
                    .font(.caption2).foregroundStyle(JIColor.muted)

                scoreChip
                progressBar

                if let note = challenge.resultNote, !note.isEmpty {
                    Text("Result: \(note)").font(.footnote).foregroundStyle(JIColor.muted)
                }

                if menuOpen {
                    VStack(alignment: .leading, spacing: 2) {
                        Button("Edit") { menuOpen = false; onEdit() }.buttonStyle(.pressableScale)
                        if challenge.status == .active {
                            Button("Mark complete") { menuOpen = false; completeNote = challenge.resultNote ?? ""; dialog = .complete }
                                .buttonStyle(.pressableScale)
                            Button("Archive") { menuOpen = false; dialog = .archive }.buttonStyle(.pressableScale)
                        }
                        if challenge.canDelete {
                            Button("Delete", role: .destructive) { menuOpen = false; dialog = .delete }.buttonStyle(.pressableScale)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }

                if let actionError { Text(actionError).font(.caption2).foregroundStyle(JIColor.danger) }
            }
        }
        .confirmationDialog("Complete this challenge?", isPresented: isPresented(.complete), titleVisibility: .visible) {
            Button("Mark complete") { runArchive(status: .completed) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(challenge.title)\" is at \(challenge.progress.count) of \(challenge.progress.target) sessions. Completing now locks in today's score.")
        }
        .confirmationDialog("Archive this challenge?", isPresented: isPresented(.archive), titleVisibility: .visible) {
            Button("Archive") { runArchive(status: .archived) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(challenge.title)\" moves to Archived. Its progress and score stay on record.")
        }
        .confirmationDialog("Delete this challenge?", isPresented: isPresented(.delete), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { runDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(challenge.title)\" has no recorded sessions yet — this can't be undone.")
        }
        .disabled(isBusy)
    }

    private func isPresented(_ kind: DialogKind) -> Binding<Bool> {
        Binding(get: { dialog == kind }, set: { if !$0 { dialog = nil } })
    }

    private func runArchive(status: ChallengeArchiveStatus) {
        let note = completeNote.trimmingCharacters(in: .whitespaces)
        Task {
            isBusy = true
            switch await model.archive(challengeId: challenge.challengeId, status: status, resultNote: note.isEmpty ? nil : note) {
            case .success: actionError = nil
            case .failure(let err): actionError = describeChallengeMutationError(err)
            }
            isBusy = false
        }
    }

    private func runDelete() {
        Task {
            isBusy = true
            if let err = await model.delete(challengeId: challenge.challengeId) {
                actionError = describeChallengeMutationError(err)
            }
            isBusy = false
        }
    }

    /// Oracle `ScoreChip`: plain neutral chip, never a verdict hue (FROZEN CONTRACT §2.4).
    private var scoreChip: some View {
        let sentence = challenge.status == .completed
            ? "Finished \(challenge.progress.count) of \(challenge.progress.target) (\(challenge.progress.executionScore)%)"
            : "\(challenge.progress.count) of \(challenge.progress.target) sessions, \(paceLabel)"
        return HStack(spacing: 8) {
            Text("\(challenge.progress.executionScore)%")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(JIColor.surface2, in: Capsule())
                .foregroundStyle(JIColor.text)
                .opacity(challenge.status == .archived ? 0.55 : 1)
            Text(sentence).font(.caption).foregroundStyle(JIColor.muted)
        }
    }

    private var paceLabel: String {
        switch challenge.progress.pace {
        case "ahead": "ahead of pace"
        case "behind": "behind pace"
        default: "on pace"
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let pct = challenge.progress.target > 0
                ? min(1, max(0, Double(challenge.progress.count) / Double(challenge.progress.target))) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(JIColor.surface3)
                Capsule().fill(JIColor.reduced).frame(width: geo.size.width * pct)
            }
        }
        .frame(height: 6)
    }
}
