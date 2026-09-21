import SwiftUI
#if canImport(WorkoutKit)
import WorkoutKit
import JICore
import JIDesign
import JIWorkouts

/// §8.5 registry entry "Send to Watch". Fixture provider/sender: the sweep never talks to a hub
/// and never schedules anything on a real Watch.
private struct L5PreviewTemplates: WorkoutTemplatesProviding {
    let templates: [WorkoutTemplate]
    func workoutTemplates() async throws -> [WorkoutTemplate] { templates }
}

private struct L5PreviewSender: WorkoutSending {
    func requestAuthorization() async throws -> Bool { true }
    func schedule(_ plan: WorkoutPlan, at date: DateComponents) async throws {}
    func remove(_ plan: WorkoutPlan, at date: DateComponents) async throws {}
    func scheduledWorkouts() async throws -> [ScheduledWorkoutPlan] { [] }
}

private struct SendToWatchNativePreviewBody: View {
    @State private var model: SendToWatchViewModel

    init() {
        let templates = l5Fixture([WorkoutTemplate].self, """
        [{"template_id": 1, "name": "Z2 easy 45", "activity": "running", "location": "outdoor", "weekdays": [1], "steps": [], "updated_at": "2026-09-20T06:00:00Z"},
         {"template_id": 2, "name": "Intervals 6×3", "activity": "running", "location": "outdoor", "weekdays": [3], "steps": [], "updated_at": "2026-09-20T06:00:00Z"}]
        """) ?? []
        _model = State(initialValue: SendToWatchViewModel(
            provider: L5PreviewTemplates(templates: templates),
            sender: L5PreviewSender(),
            seededTemplates: templates
        ))
    }

    var body: some View {
        SendToWatchSheet(model: model).nativeContent
            .jiTheme(.native)
            .background(JITheme.native.color(.bg))
    }
}
#endif

/// The registry's array literal cannot carry a `#if`, so the entry's view is always a type —
/// on a platform without WorkoutKit it is simply empty.
struct SendToWatchNativePreview: View {
    var body: some View {
        #if canImport(WorkoutKit)
        SendToWatchNativePreviewBody()
        #else
        EmptyView()
        #endif
    }
}
