import SwiftUI

/// One driver of the readiness score (e.g. HRV, RHR, sleep, ACWR) with a signed contribution
/// magnitude — larger `abs(magnitude)` means it moved readiness more, in either direction.
// nonisolated: pure data type — ContributorBreakdownTests' nonisolated `@Test` funcs
// construct it and form key paths to its properties (`ranked.map(\.id)`), both of which
// require the *type*, not just its init, to opt out of JIDesign's MainActor default
// isolation (matching DriverBar's stored-property use in DriverBars.swift).
public nonisolated struct ReadinessContributor: Identifiable, Equatable, Sendable {
    public let id: String, label: String, value: Double?, magnitude: Double
    public init(id: String, label: String, value: Double?, magnitude: Double) {
        self.id = id; self.label = label; self.value = value; self.magnitude = magnitude
    }
}

/// Pure ranking: highest `abs(magnitude)` first. `sorted(by:)` is a stable sort (Swift 5+), so
/// equal-magnitude contributors keep their input order — testable independent of any view.
public nonisolated func rankedContributors(_ contributors: [ReadinessContributor]) -> [ReadinessContributor] {
    contributors.sorted { abs($0.magnitude) > abs($1.magnitude) }
}

/// Ranked readiness contributor breakdown. Bars are contributor/component bars, not the
/// score/band itself — NEUTRAL (`mutedNested`) always, never the reserved verdict green.
public struct ContributorBreakdown: View {
    let contributors: [ReadinessContributor]
    public init(contributors: [ReadinessContributor]) { self.contributors = contributors }

    public var body: some View {
        let ranked = rankedContributors(contributors)
        let maxMagnitude = ranked.map { abs($0.magnitude) }.max() ?? 0
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ranked) { c in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(c.label).font(.caption).foregroundStyle(JIColor.muted)
                        Spacer()
                        Text(valueText(c.value)).font(.caption).foregroundStyle(JIColor.text)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(JIColor.surface3)
                            if maxMagnitude > 0 {
                                Capsule().fill(JIColor.mutedNested)
                                    .frame(width: g.size.width * CGFloat(abs(c.magnitude) / maxMagnitude))
                            }
                        }
                    }.frame(height: 6)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(c.label) \(valueText(c.value))")
            }
        }
    }

    private func valueText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }
}
