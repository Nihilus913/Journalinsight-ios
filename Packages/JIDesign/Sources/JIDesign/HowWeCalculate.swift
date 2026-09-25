import SwiftUI

/// B-57 §1: one numbered explainer step. `id` = title (titles are unique within one explainer).
public nonisolated struct HowWeCalculateStep: Sendable, Equatable, Identifiable {
    public let title: String, body: String
    public var id: String { title }
    public init(title: String, body: String) { self.title = title; self.body = body }
}

public nonisolated func howWeCalculateStepAccessibilityLabel(index: Int, count: Int, step: HowWeCalculateStep) -> String {
    "Step \(index + 1) of \(count). \(step.title). \(step.body)"
}

public struct HowWeCalculate: View {
    let title: String, steps: [HowWeCalculateStep], note: String?
    @Environment(\.jiTheme) private var theme
    public init(title: String, steps: [HowWeCalculateStep], note: String? = nil) { self.title = title; self.steps = steps; self.note = note }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).jiFont(.cardTitle).foregroundStyle(theme.color(.text)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Surface(level: 1) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").jiFont(.footnote, weight: .bold).foregroundStyle(theme.color(.info))
                                .frame(width: 24, height: 24).background(theme.color(.nested), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(step.body).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(howWeCalculateStepAccessibilityLabel(index: i, count: steps.count, step: step))
                        if i < steps.count - 1 { Divider().overlay(theme.color(.hairlineNested)) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let note {
                Text(note).jiFont(.caption).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The "How we calculate this ›" row; pushes the explainer (needs an enclosing NavigationStack).
public struct HowWeCalculateLink: View {
    let linkTitle: String, title: String, steps: [HowWeCalculateStep], note: String?
    @Environment(\.jiTheme) private var theme
    public init(_ linkTitle: String = "How we calculate this", title: String, steps: [HowWeCalculateStep], note: String? = nil) {
        self.linkTitle = linkTitle; self.title = title; self.steps = steps; self.note = note
    }
    public var body: some View {
        NavigationLink {
            ScrollView { HowWeCalculate(title: title, steps: steps, note: note).padding(20) }
                .background(theme.color(.bg))
                .navigationTitle(title)
        } label: {
            Text("\(linkTitle) ›").jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.info))
                .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel(linkTitle)
        .accessibilityIdentifier("how-we-calculate-link")
    }
}
