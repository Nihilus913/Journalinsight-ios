import SwiftUI
import JIDesign

// W-B102 C-4 (BP-23a mockup frame 02): the one Today card that asks for something. It exists only
// while a rule is live (no "nothing to ask" placeholder, nothing while calibrating).

extension EnvironmentValues {
    /// The data-triggered check-in model (nil in previews / package tests → no card).
    @Entry public var checkInPrompt: CheckInPromptModel?
    /// Opens the check-in sheet with the live prompt (the App owns the vaulted Mind model).
    @Entry public var openCheckIn: (@MainActor () -> Void)?
}

/// Pure copy for the card (testable without rendering).
public nonisolated struct CheckInPromptCardContent: Equatable, Sendable {
    public var header = "Check-in"
    public var title: String
    public var body: String
    public var morningsLine: String?
    public var primary = "Check in · 10 s"
    public var secondary = "Not today"
    public var footer = "Asked at most once a day. " + CheckInTrigger.neverChangesLine

    public init(_ prompt: CheckInPrompt) {
        title = prompt.title
        body = prompt.body
        morningsLine = prompt.morningsLine.map { "Mornings " + $0 }
    }
}

public struct CheckInPromptCard: View {
    let prompt: CheckInPrompt
    let onCheckIn: () -> Void
    let onNotToday: () -> Void
    @Environment(\.jiTheme) private var theme

    public init(prompt: CheckInPrompt, onCheckIn: @escaping () -> Void, onNotToday: @escaping () -> Void) {
        self.prompt = prompt; self.onCheckIn = onCheckIn; self.onNotToday = onNotToday
    }

    public var body: some View {
        let c = CheckInPromptCardContent(prompt)
        Surface(level: 1, padding: JISpacing.s4, tint: theme.color(.reduced)) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                Text(c.title).jiFont(.cardTitle)
                Text(c.body).jiFont(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let line = c.morningsLine {
                    Text(line).jiFont(.caption, tint: .muted).fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: JISpacing.s2) { buttons(c) }
                    VStack(alignment: .leading, spacing: JISpacing.s2) { buttons(c) }
                }
                Text(c.footer).jiFont(.caption, tint: .muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.checkin.card")
    }

    @ViewBuilder
    private func buttons(_ c: CheckInPromptCardContent) -> some View {
        Button(c.primary, action: onCheckIn).buttonStyle(.jiPrimary).accessibilityIdentifier("today.checkin.open")
        Button(c.secondary, action: onNotToday).buttonStyle(.jiSecondary).accessibilityIdentifier("today.checkin.notToday")
    }
}

/// CheckInSheet's "Why this prompt" strip (mockup frame 03) — only when opened from a prompt.
struct CheckInWhySection: View {
    let prompt: CheckInPrompt
    var body: some View {
        Section("Why this prompt") {
            Text(prompt.why).jiFont(.subheadline).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("checkin.why")
        }
    }
}
