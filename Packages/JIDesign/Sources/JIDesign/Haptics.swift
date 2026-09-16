import SwiftUI

/// The interactions that carry a haptic. One case per ladder rung — adding a new
/// interaction means adding a case here, not a new ad-hoc `.sensoryFeedback` call
/// at the call site.
public enum JIHapticEvent: Sendable, Equatable, CaseIterable {
    case pressIn
    case toggleOn
    case toggleOff
    case success
    case warning
}

/// The haptic ladder: maps each `JIHapticEvent` to the feedback it fires.
///
/// Scaffolded so Q#2 (spec §11.2 / DESIGN-5 — keep the four custom Android
/// `CHHapticPattern` recipes vs simplify to stock `.sensoryFeedback` cases) is a
/// **one-file swap**: everything that wants a haptic calls `JIHaptic.feedback(for:)`
/// and never touches `SensoryFeedback` or `CHHapticEngine` directly. Swapping the
/// engine later means editing the bodies below, not any call site.
public enum JIHaptic {
    /// The stock `SensoryFeedback` currently wired for each event. Swap this
    /// mapping (or replace its use with a `CHHapticPattern` player) to resolve Q#2
    /// without touching any call site.
    public nonisolated static func feedback(for event: JIHapticEvent) -> SensoryFeedback {
        switch event {
        case .pressIn: .selection
        case .toggleOn: .impact(weight: .light)
        case .toggleOff: .impact(weight: .light, intensity: 0.6)
        case .success: .success
        case .warning: .warning
        }
    }
}

/// Fires `event`'s ladder feedback when `trigger` transitions `false -> true` —
/// the shared "only on press-in, not release" gate every haptic-carrying control
/// should use instead of a bespoke `.sensoryFeedback` call.
public struct JIHapticModifier: ViewModifier {
    let event: JIHapticEvent
    let trigger: Bool
    public init(event: JIHapticEvent, trigger: Bool) {
        self.event = event
        self.trigger = trigger
    }
    public func body(content: Content) -> some View {
        content.sensoryFeedback(JIHaptic.feedback(for: event), trigger: trigger) { old, new in new && !old }
    }
}

public extension View {
    /// Routes a boolean press/toggle trigger through the `JIHaptic` ladder for `event`,
    /// firing only on the `false -> true` edge (press-in, never release).
    func jiHaptic(_ event: JIHapticEvent, trigger: Bool) -> some View {
        modifier(JIHapticModifier(event: event, trigger: trigger))
    }
}
