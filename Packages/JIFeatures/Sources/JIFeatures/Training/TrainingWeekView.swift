import SwiftUI

/// B-57 W5 B2 stub — B3 replaces the body with the "Your week" board.
public struct TrainingWeekView: View {
    let model: TrainingViewModel
    public init(model: TrainingViewModel) { self.model = model }
    public var body: some View { Text("Your week") }
}
