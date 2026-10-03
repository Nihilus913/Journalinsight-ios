import AppIntents
import JIWorkouts

/// W-B38-B B-6 (gap #31): the Action Button starts a strength session. A `StartWorkoutIntent`
/// is what the Ultra's Action Button lists under "Workout" for a third-party app; it opens the
/// app and hands the start to `StrengthSessionLauncher` (replayed if the UI is not up yet).
enum StrengthWorkoutStyle: String, AppEnum {
    case strength

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workout"
    static let caseDisplayRepresentations: [StrengthWorkoutStyle: DisplayRepresentation] = [
        .strength: DisplayRepresentation(title: "Strength", image: .init(systemName: "dumbbell.fill")),
    ]
}

struct StartStrengthSessionIntent: StartWorkoutIntent {
    static let title: LocalizedStringResource = "Start Strength Session"

    @Parameter(title: "Workout")
    var workoutStyle: StrengthWorkoutStyle

    static var suggestedWorkouts: [StartStrengthSessionIntent] { [StartStrengthSessionIntent(style: .strength)] }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Strength", image: .init(systemName: "dumbbell.fill"))
    }

    init() {}

    func perform() async throws -> some IntentResult {
        await StrengthSessionLauncher.shared.startFromIntent()
        return .result()
    }
}
