import Foundation
import Observation
import JICore

/// W-B38-B B-10 — browse / search the one exercise catalogue; a pick hands the exercise to the
/// running session (the strength log adds it). Entries are de-duplicated by key, first wins.
@Observable @MainActor
public final class ExerciseLibraryViewModel {
    public struct Group: Identifiable, Equatable {
        public let title: String
        public let entries: [ExerciseLibraryEntry]
        public var id: String { title }
    }

    public let entries: [ExerciseLibraryEntry]
    public var query = ""
    public private(set) var lastPicked: String?
    private let onPick: (ExerciseOption) -> Void

    /// `options` = `WorkoutExerciseCatalogue.options(from: templates)` (catalogue + library extras).
    public init(options: [ExerciseOption], onPick: @escaping (ExerciseOption) -> Void = { _ in }) {
        var seen = Set<String>()
        entries = options.compactMap { o in
            guard seen.insert(o.key).inserted else { return nil }
            return ExerciseLibraryEntry(option: o, preview: ExerciseLibrary.preview(for: o))
        }
        self.onPick = onPick
    }

    public var filtered: [ExerciseLibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { e in
            e.option.key.lowercased().contains(q) || e.preview.muscles.contains { $0.lowercased().contains(q) }
                || (e.preview.equipment?.lowercased().contains(q) ?? false)
        }
    }

    /// The filtered entries grouped by primary muscle, groups A→Z, entries in catalogue order.
    public var groups: [Group] {
        let byMuscle = Dictionary(grouping: filtered, by: \.preview.primaryMuscle)
        return byMuscle.keys.sorted().map { Group(title: $0, entries: byMuscle[$0] ?? []) }
    }

    public func pick(_ entry: ExerciseLibraryEntry) {
        lastPicked = entry.option.key
        onPick(entry.option)
    }
}
