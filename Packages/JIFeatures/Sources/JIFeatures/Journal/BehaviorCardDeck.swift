import SwiftUI
import Observation
import JIDesign
import JIPersistence

// W8-L2 (P-journal). Full port of `mobile/src/components/journal/BehaviorCardDeck.tsx` (288 L),
// replacing the W4 static placeholder. A small Tinder-style deck over `BehaviorDeck.cards`:
// swipe right (or the Yes button) logs "yes", swipe left (or No) logs "no", and the card is
// dismissed either way — answering advances to the next card in the cards' own fixed order.
// Answers persist per calendar day (`BehaviorLogStore`, RN's `behavior_log.v1.<date>` pref) so
// leaving and returning the same day preserves progress, and a new day starts every card fresh.
// Swift-only addition per the W8 card: an Undo affordance after each answer that removes the
// persisted row and puts the card back on top.
//
// Reduced motion is handled the way the oracle documents: the drag gesture is skipped entirely,
// not softened, and the Yes/No buttons (always rendered) are the one concrete fallback action.
//
// Fonts: L3's `JITypography` does not exist in this lane's tree, so — per the card — every text
// here uses a semantic `Font.TextStyle` (Dynamic Type follows for free), never a fixed size.

/// One answered card the user may still take back (Swift-only undo).
public nonisolated struct BehaviorUndoEntry: Sendable, Equatable {
    public let card: BehaviorCard
    public let answer: BehaviorAnswer
}

/// Screen state for the deck (oracle: the component's own hooks). Framework-free apart from
/// `@Observable`, so `BehaviorDeckViewModelTests` drives the whole gesture/persist/undo path.
@Observable @MainActor
public final class BehaviorDeckViewModel {
    /// The calendar day answers are keyed under; refreshed by `rolloverIfNeeded()` unless the
    /// initialiser pinned a `date` (tests / previews).
    public private(set) var day: String
    public private(set) var responses: DeckResponses = [:]
    public private(set) var undoEntry: BehaviorUndoEntry?
    /// Measured width of the top card — the swipe-distance bar scales with it.
    public var cardWidth: Double = BehaviorDeck.preLayoutCardWidth
    /// Mirror of the OS reduce-motion setting; while on, no drag is ever claimed.
    public var reduceMotion = false
    /// Non-nil after a store write failed (rule 5: never silent). The in-memory deck state is
    /// already applied optimistically, exactly like the oracle's best-effort persist.
    public private(set) var persistError: String?

    private let store: BehaviorLogStore?
    private let cards: [BehaviorCard]
    private let pinnedDate: String?
    private let now: () -> Date
    private let calendar: Calendar

    public init(
        store: BehaviorLogStore?,
        cards: [BehaviorCard] = BehaviorDeck.cards,
        date: String? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.cards = cards
        self.pinnedDate = date
        self.now = now
        self.calendar = calendar
        self.day = date ?? BehaviorDeck.dayKey(for: now(), calendar: calendar)
    }

    public var deck: [BehaviorCard] { BehaviorDeck.orderDeck(cards, answered: responses) }
    public var top: BehaviorCard? { deck.first }
    public var remaining: Int { deck.count }
    public var isComplete: Bool { top == nil }

    /// `loadBehaviorResponses(day)` on mount. A missing store (no database) reads as an empty
    /// day rather than a crash.
    public func load() {
        responses = (try? store?.load(date: day)) ?? [:]
    }

    /// Day rollover: when the local calendar day has moved on since the last load, re-key to
    /// the new day (every card fresh) and drop any pending undo, which belonged to yesterday.
    /// Returns whether a rollover happened. No-op when the initialiser pinned a date.
    @discardableResult
    public func rolloverIfNeeded() -> Bool {
        guard pinnedDate == nil else { return false }
        let today = BehaviorDeck.dayKey(for: now(), calendar: calendar)
        guard today != day else { return false }
        day = today
        undoEntry = nil
        load()
        return true
    }

    /// `commit(card, answer)`: optimistic in-memory update + best-effort persist.
    public func commit(_ card: BehaviorCard, _ answer: BehaviorAnswer) {
        responses[card.id] = answer
        undoEntry = BehaviorUndoEntry(card: card, answer: answer)
        do {
            try store?.record(date: day, cardId: card.id, answer: answer)
            persistError = nil
        } catch {
            persistError = "Couldn't save this answer — it won't survive a restart."
        }
    }

    /// Undo the most recent answer: removes the persisted row and puts the card back on top.
    public func undo() {
        guard let entry = undoEntry else { return }
        responses.removeValue(forKey: entry.card.id)
        undoEntry = nil
        do {
            try store?.remove(date: day, cardId: entry.card.id)
            persistError = nil
        } catch {
            persistError = "Couldn't undo on disk — the answer may come back after a restart."
        }
    }

    /// E16-12 gate: whether a drag with this cumulative movement is a swipe (vs a scroll).
    public func shouldClaimSwipe(dx: Double, dy: Double) -> Bool {
        top != nil && BehaviorDeck.shouldClaimSwipe(dx: dx, dy: dy, reduceMotion: reduceMotion)
    }

    /// `onResponderRelease`: resolves the drag against the distance/velocity bars. Commits and
    /// returns the answer, or returns `nil` — snap back, nothing recorded. `elapsedMs` is the
    /// whole gesture's duration; average velocity `dx / dt` catches a fast flick.
    @discardableResult
    public func releaseSwipe(dx: Double, elapsedMs: Double) -> BehaviorAnswer? {
        guard let top, !reduceMotion else { return nil }
        let dt = max(1, elapsedMs)
        guard let outcome = BehaviorDeck.resolveSwipeOutcome(dx: dx, vx: dx / dt, cardWidth: cardWidth) else { return nil }
        commit(top, outcome)
        return outcome
    }
}

/// Behaviour check-in deck (oracle: `BehaviorCardDeck.tsx`). Mounted by `JournalView`.
public struct BehaviorCardDeck: View {
    @Environment(\.jiTheme) private var theme
    @State private var model: BehaviorDeckViewModel
    @State private var dragOffset: CGFloat = 0
    @State private var dragClaimed = false
    @State private var dragStart: Date?
    @State private var buttonHaptic = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The on-disk store the Journal mount uses: `JournalView` only owns the mount line and
    /// `JournalViewModel` keeps its `AppDatabase` private, so the deck resolves the same
    /// backed-up `journalinsight.sqlite` file itself — the idiom `WeeklyPlanStore.onDisk`
    /// already documents (GRDB supports several pools against one file). Lazily initialised;
    /// a failure degrades to "not persisted", never a crash (rule 5).
    public static let onDiskStore: BehaviorLogStore? = (try? AppDatabase.onDisk()).map { BehaviorLogStore(prefs: PrefStore(db: $0)) }

    public init(store: BehaviorLogStore? = BehaviorCardDeck.onDiskStore, date: String? = nil) {
        _model = State(initialValue: BehaviorDeckViewModel(store: store, date: date))
    }

    public init(model: BehaviorDeckViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Surface(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                if let top = model.top {
                    header(trailing: "\(model.remaining) left today")
                    card(top)
                } else {
                    header(trailing: nil)
                    Text("All logged for today.").font(.subheadline).foregroundStyle(theme.color(.text))
                    Text("Every check-in answered — see you tomorrow.").font(.caption).foregroundStyle(theme.color(.muted))
                }
                if let error = model.persistError {
                    Text(error).font(.caption).foregroundStyle(theme.color(.reduced))
                        .accessibilityIdentifier("behavior-card-persist-error")
                }
                if let undo = model.undoEntry {
                    Button {
                        buttonHaptic += 1
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35)) { model.undo() }
                    } label: {
                        Label("Undo \(undo.answer.rawValue) — \(undo.card.title)", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.color(.info))
                    }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Undo \(undo.card.title) — \(undo.answer.rawValue)")
                    .accessibilityIdentifier("behavior-card-undo")
                }
            }
        }
        // Identifier mirrors the oracle's `testID="behavior-card-deck"`.
        .accessibilityIdentifier("behavior-card-deck")
        .sensoryFeedback(JIHaptic.feedback(for: .pressIn), trigger: buttonHaptic)
        .onAppear {
            model.reduceMotion = reduceMotion
            model.load()
        }
        .onChange(of: reduceMotion) { _, new in model.reduceMotion = new }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.rolloverIfNeeded() { dragOffset = 0 }
        }
    }

    private func header(trailing: String?) -> some View {
        HStack {
            Text("Behavior check-in").font(.caption.weight(.bold)).textCase(.uppercase).kerning(0.6)
                .foregroundStyle(theme.color(.muted))
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("behavior-card-remaining")
            }
        }
    }

    private func card(_ top: BehaviorCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(top.title).font(.headline).foregroundStyle(theme.color(.text))
            Text(top.prompt).font(.subheadline).foregroundStyle(theme.color(.text))
            Text(top.detail).font(.caption).foregroundStyle(theme.color(.muted))

            HStack(spacing: 10) {
                answerButton("No", answer: .no, tint: theme.color(.danger), card: top)
                answerButton("Yes", answer: .yes, tint: theme.color(.go), card: top)
            }
            .padding(.top, 8)

            Text("Swipe right for yes, left for no — or use the buttons.")
                .font(.caption2).foregroundStyle(theme.color(.muted))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.nested), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.color(.hairlineNested), lineWidth: 1))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.cardWidth = Double($0) }
        .offset(x: dragOffset)
        .gesture(swipeGesture, including: reduceMotion ? .subviews : .all)
        .id(top.id) // a freshly-arrived top card always starts undragged
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("behavior-card-top")
    }

    private func answerButton(_ label: String, answer: BehaviorAnswer, tint: Color, card: BehaviorCard) -> some View {
        Button {
            buttonHaptic += 1
            withAnimation(reduceMotion ? nil : .spring(response: 0.35)) { model.commit(card, answer) }
        } label: {
            Text(label).font(.footnote.weight(.bold)).foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.pressableScale)
        // Labels verbatim from the oracle: `${top.title} — yes|no`.
        .accessibilityLabel("\(card.title) — \(answer.rawValue)")
        .accessibilityIdentifier("behavior-card-\(answer.rawValue)")
    }

    /// Raw-responder port: `minimumDistance` is the dead zone, the first `onChanged` decides
    /// horizontal-vs-vertical intent (a vertical drag is never claimed and scrolls the parent),
    /// and release resolves distance/average-velocity against the card width.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: BehaviorDeck.horizontalIntent, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = Date()
                    dragClaimed = model.shouldClaimSwipe(dx: value.translation.width, dy: value.translation.height)
                }
                guard dragClaimed else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                defer { dragStart = nil; dragClaimed = false }
                guard dragClaimed else { return }
                let elapsed = (dragStart.map { Date().timeIntervalSince($0) } ?? 0) * 1000
                let outcome = model.releaseSwipe(dx: value.translation.width, elapsedMs: elapsed)
                if outcome != nil {
                    dragOffset = 0
                } else if reduceMotion {
                    dragOffset = 0
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { dragOffset = 0 }
                }
            }
    }
}
