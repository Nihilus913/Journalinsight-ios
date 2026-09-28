import SwiftUI
import JICore
import JIDesign

/// W-B40 L2 — fixture screens for the library, the editor (cardio, and strength + run) and the
/// import sheet: previews, the §8.5 sweep (registry entries are added at integration) and the
/// lane's sim check. Spec-shaped sample rows (spec §2.1), never a hub and never Toby's data.
public nonisolated enum WorkoutsFixture {
    public static let templates: [WorkoutTemplate] = {
        let json = Data(#"""
        [{"template_id": 3, "name": "Norwegian 4×4", "activity": "running", "location": "outdoor", "weekdays": [0, 4], "steps": [],
          "segments": [{"sport": "running", "steps": [
            {"purpose": "warmup", "end": {"type": "time", "seconds": 600}, "target": {"type": "hr_range", "lo": 100, "hi": 140}, "repeat": 1},
            {"purpose": "work", "end": {"type": "time", "seconds": 240}, "target": {"type": "hr_range", "lo": 160, "hi": 175}, "repeat": 4},
            {"purpose": "recovery", "end": {"type": "time", "seconds": 180}, "target": {"type": "hr_range", "lo": 100, "hi": 140}, "repeat": 4},
            {"purpose": "cooldown", "end": {"type": "time", "seconds": 300}, "target": {"type": "hr_range", "lo": 100, "hi": 140}, "repeat": 1}]}],
          "garmin": {"workout_id": 1, "current": true, "pushed_at": "2026-09-28T09:00:00Z"}, "updated_at": "2026-09-28T08:00:00Z"},
         {"template_id": 1, "name": "Long Run Zone 2", "activity": "running", "location": "outdoor", "weekdays": [6], "steps": [],
          "segments": [{"sport": "running", "steps": [
            {"purpose": "warmup", "end": {"type": "time", "seconds": 600}, "target": {"type": "none"}, "repeat": 1},
            {"purpose": "work", "end": {"type": "time", "seconds": 4800}, "target": {"type": "hr_zone", "zone": 2}, "repeat": 1},
            {"purpose": "cooldown", "end": {"type": "lap"}, "target": {"type": "none"}, "repeat": 1}]}],
          "garmin": {"workout_id": 2, "current": false, "pushed_at": null}, "updated_at": "2026-09-28T08:00:00Z"},
         {"template_id": 7, "name": "Friday", "activity": "running", "location": "outdoor", "weekdays": [4], "steps": [],
          "segments": [{"sport": "strength", "steps": [
            {"purpose": "warmup", "end": {"type": "time", "seconds": 300}, "target": {"type": "none"}, "repeat": 1, "description": "Rope jumping"},
            {"exercise_key": "Barbell Bench Press", "garmin_category": "BENCH_PRESS", "garmin_exercise": "BARBELL_BENCH_PRESS", "sets": 3, "reps": 12, "weight_kg": 40, "rest_seconds": 120},
            {"exercise_key": "Barbell Row", "garmin_category": "ROW", "garmin_exercise": "BARBELL_ROW", "sets": 3, "reps": 12, "weight_kg": 50, "rest_seconds": 120},
            {"exercise_key": "Plank", "garmin_category": "PLANK", "garmin_exercise": "PLANK", "sets": 3, "seconds": 45, "rest_seconds": 60}]},
            {"sport": "running", "steps": [
            {"purpose": "work", "end": {"type": "time", "seconds": 3600}, "target": {"type": "hr_zone", "zone": 2}, "repeat": 1}]}],
          "description": "Strength first, then an easy run", "garmin": null, "updated_at": "2026-09-28T08:00:00Z"},
         {"template_id": 9, "name": "Drill Workout", "activity": "running", "location": "outdoor", "weekdays": [], "steps": [],
          "segments": [{"sport": "running", "steps": [
            {"purpose": "warmup", "end": {"type": "lap"}, "target": {"type": "none"}, "repeat": 1},
            {"purpose": "work", "end": {"type": "distance", "meters": 800}, "target": {"type": "hr_zone", "zone": 4}, "repeat": 1}]}],
          "garmin": {"workout_id": 4, "current": true, "pushed_at": null}, "updated_at": "2026-09-28T08:00:00Z"}]
        """#.utf8)
        return (try? JSON.decoder.decode([WorkoutTemplate].self, from: json)) ?? []
    }()
}

public struct WorkoutLibraryNativePreview: View {
    @State private var model = WorkoutLibraryViewModel(seeded: WorkoutsFixture.templates)
    public init() {}
    public var body: some View {
        NavigationStack { WorkoutLibraryView(model: model, onSendToWatch: { _ in }) }
            .jiTheme(.native)
    }
}

public struct WorkoutEditorNativePreview: View {
    private let index: Int
    @State private var library = WorkoutLibraryViewModel(seeded: WorkoutsFixture.templates)
    /// 0 = Norwegian 4×4 (cardio), 2 = Friday (strength + run).
    public init(index: Int = 0) { self.index = index }
    public var body: some View {
        let t = WorkoutsFixture.templates.indices.contains(index) ? WorkoutsFixture.templates[index] : nil
        WorkoutEditorSheet(model: WorkoutEditorViewModel(template: t, exerciseOptions: library.exerciseOptions) { _ in .saved },
                           library: library, onSendToWatch: { _ in })
    }
}

public struct ImportFromGarminNativePreview: View {
    @State private var model = WorkoutLibraryViewModel(seeded: WorkoutsFixture.templates)
    public init() {}
    public var body: some View { ImportFromGarminSheet(model: model) }
}
