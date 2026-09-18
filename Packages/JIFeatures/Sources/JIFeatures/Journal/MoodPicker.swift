import SwiftUI
import JIDesign

/// Journal mood scale (oracle: `mobile/src/journal/mood.ts`). Ordering, emoji, and valence are
/// ported verbatim — `MOODS` is the canonical display order every other Journal file iterates in.
public enum Mood: String, Sendable, Equatable, CaseIterable, Codable {
    case great, good, okay, bad, terrible
}

public nonisolated let MOODS: [Mood] = [.great, .good, .okay, .bad, .terrible]

private nonisolated let moodEmojiTable: [Mood: String] = [
    .great: "😄", .good: "🙂", .okay: "😐", .bad: "😞", .terrible: "😢",
]
private nonisolated let moodValenceTable: [Mood: Double] = [
    .great: 1, .good: 0.5, .okay: 0, .bad: -0.5, .terrible: -1,
]

public nonisolated func moodEmoji(_ mood: Mood) -> String { moodEmojiTable[mood] ?? "—" }
public nonisolated func moodValence(_ mood: Mood) -> Double { moodValenceTable[mood] ?? 0 }

/// A horizontal row of tappable mood emoji (oracle: RN's inline mood row in `EntrySheet.tsx`).
/// `selection` is optional — clearing it (tap the already-selected mood again) is how RN lets a
/// mood be left unset on an entry.
public struct MoodPicker: View {
    @Binding var selection: Mood?
    public init(selection: Binding<Mood?>) { self._selection = selection }

    public var body: some View {
        HStack(spacing: 10) {
            ForEach(MOODS, id: \.self) { mood in
                Button {
                    selection = (selection == mood) ? nil : mood
                } label: {
                    Text(moodEmoji(mood))
                        .jiFont(.title)
                        .padding(8)
                        .background(
                            Circle().fill(selection == mood ? JIColor.info.opacity(0.25) : Color.clear)
                        )
                }
                .buttonStyle(.pressableScale)
                .jiHaptic(.pressIn, trigger: selection == mood)
                .accessibilityLabel(mood.rawValue)
                .accessibilityIdentifier("mood-\(mood.rawValue)")
                .accessibilityAddTraits(selection == mood ? .isSelected : [])
            }
        }
    }
}
