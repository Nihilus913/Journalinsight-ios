import ActivityKit
import Foundation
import JICore

/// W-B38-B B-7 — ActivityKit attributes for the strength-session Live Activity. Member of BOTH the
/// app (which requests/updates/ends it, `StrengthSessionActivityController`) and the widget
/// extension (which draws it, `StrengthSessionActivityWidget`) — the same two-target pattern as
/// `VerdictActivityAttributes` (`project.yml` JournalInsight sources). The content state is the
/// Foundation-only `JICore.StrengthSessionActivityState` so package tests cover it without
/// ActivityKit.
public nonisolated struct StrengthSessionActivityAttributes: ActivityAttributes {
    public typealias ContentState = StrengthSessionActivityState

    /// The session's start (static for the activity's life): drives the elapsed clock.
    public var startedAt: Date
    public var title: String

    public init(startedAt: Date, title: String = "Strength") {
        self.startedAt = startedAt
        self.title = title
    }
}
