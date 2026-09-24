import SwiftUI
import JICore
import JIDesign

/// E14-D7 / W5b-L1 — the Data Quality detail screen (oracle `mobile/app/data-quality.tsx`).
///
/// The hub already computes a per-(source, metric) composite quality score, a freshness traffic
/// light, and a source-trust table, but the app only ever surfaced a single freshness line on
/// Today (`DataFreshnessBadge`) with no way to drill in. This is that drill-down: every quality
/// row's composite plus its inspectable components (freshness days/coverage, range validity,
/// trust, and the standing provenance gap), worst first, followed by the source-trust table with
/// its reasons.
///
/// Null-graceful throughout — an omitted sub-score reads as "not scored" text, never as a blank or
/// a fabricated number (rule 5).
public struct DataQualityView: View {
    @Environment(\.jiTheme) private var theme
    @Bindable private var model: DataQualityViewModel

    public init(model: DataQualityViewModel) { self.model = model }

    public var body: some View {
        List {
            if !model.hubReachable, model.fetchedAt != nil {
                Section { StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable) }
            }
            switch model.phase {
            case .idle, .loading: loading
            case .error(let message): errorCard(message)
            case .empty: emptyCard
            case .loaded:
                sourcesSummarySection
                sourcesSection
                qualitySection
                trustSection
            }
        }
        .jiNativeFormChrome()
        // B-46 item 5: `readableColumn()` puts a hard `frame(maxWidth: 720)` on whatever it wraps.
        // On a `ScrollView`'s inner `VStack` (every other screen) that is a readable-width cap; on
        // a `List` it OVERRIDES the list's own width, so at 393 pt the list laid out 720 pt wide
        // and its rows were clipped away — exactly the "floating card on black, title + subtitle,
        // no rows" Toby saw. A `List` already handles readable width per platform (§8.2); it does
        // not need, and must not get, a fixed frame.

        .jiTheme(.native)
        // §5: the hand-drawn large title is the system's; the oracle's `ScreenHeader info=…`
        // copy becomes the navigation subtitle, verbatim.
        .navigationTitle("Data quality")
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var loading: some View {
        Section { SkeletonBlock(height: 260) }
            .accessibilityIdentifier("dataQuality.loading")
    }

    /// Oracle's error card: its own copy plus a Retry that refetches all three reports.
    private func errorCard(_ message: String) -> some View {
        Section {
            Text(message).foregroundStyle(theme.color(.text))
            Button("Retry") { Task { await model.refresh() } }
                .accessibilityLabel("Retry loading data quality")
                .accessibilityIdentifier("dataQuality.retry")
        }
    }

    private var emptyCard: some View {
        Section {
            Text("No data-quality rows yet.")
                .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                .accessibilityIdentifier("dataQuality.empty")
        }
    }

    // MARK: - B-57 W1 board: Sources fresh today + Sources rows

    private var sourcesSummarySection: some View {
        let summary = model.sourceSummary
        let total = summary.sources.count
        return Section {
            BoardSummaryCard(
                systemImage: "checkmark.shield", title: "Sources fresh today",
                trailing: model.fetchedAt.map { "as of \($0.formatted(date: .omitted, time: .shortened))" },
                value: total == 0 ? nil : "\(summary.fresh)", unit: "of \(total)",
                valueTint: summary.stale == 0 ? .go : .reduced,
                status: total == 0
                    ? BoardStatus(word: "No data", systemImage: "minus", role: .muted)
                    : summary.stale == 0
                        ? BoardStatus(word: "All fresh", systemImage: "checkmark", role: .go)
                        : BoardStatus(word: "\(summary.stale) stale", systemImage: "exclamationmark.triangle", role: .danger),
                segments: summary.sources.map { role(for: $0.state) },
                note: sourcesNote(summary)
            )
            .accessibilityIdentifier("dataQuality.summary")
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(model.sourceSummary.sources) { source in
                JIRow(title: dataQualitySourceDisplay(source.source)) {
                    BoardStatusLabel(word: stateWord(source),
                                     systemImage: source.state == .green ? "checkmark" : "exclamationmark.triangle",
                                     role: role(for: source.state))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dataQuality.source.\(source.source)")
            }
        } header: {
            Text("Sources")
        }
    }

    private func stateWord(_ s: DataQualitySourceState) -> String {
        switch s.state {
        case .green: "Fresh"
        case .amber, .red: s.daysStale.map { "Stale \($0) d" } ?? "Not arriving"
        }
    }

    private func sourcesNote(_ summary: DataQualitySourceSummary) -> String? {
        guard !summary.sources.isEmpty else { return nil }
        let stale = summary.sources.filter { $0.state != .green }
        if stale.isEmpty { return "Every source is current." }
        return "Stale: " + stale.map { s in
            dataQualitySourceDisplay(s.source) + (s.daysStale.map { " (\($0) d)" } ?? "")
        }.joined(separator: ", ") + "."
    }

    private func role(for state: FreshnessState) -> JIColorRole {
        switch state {
        case .green: .go
        case .amber: .reduced
        case .red: .danger
        }
    }

    // MARK: - Per-source quality

    private var qualitySection: some View {
        Section {
            if model.sortedScores.isEmpty {
                Text("No data-quality rows yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
            } else {
                ForEach(model.sortedScores) { entry in
                    qualityRow(entry, fresh: model.freshness(for: entry))
                }
            }
        } header: {
            Text("Per-source quality")
                .accessibilityIdentifier("dataQuality.section.quality")
        } footer: {
            if let gap = model.provenanceGap {
                Text(gap).accessibilityIdentifier("dataQuality.provenanceGap")
            }
        }
    }

    private func qualityRow(_ entry: QualityScoreEntry, fresh: FreshnessEntry?) -> some View {
        let tone = dataQualityCompositeTone(entry.composite)
        return VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    toneDot(tone)
                    Text(entry.metricLabel).font(.footnote.bold()).foregroundStyle(theme.color(.text))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text("\(Int((entry.composite * 100).rounded()))%")
                        .font(.caption.bold()).foregroundStyle(color(tone))
                }
                Text(dataQualitySourceDisplay(entry.source)).font(.caption2).foregroundStyle(theme.color(.muted))

                VStack(alignment: .leading, spacing: 4) {
                    freshnessLine(fresh)
                    detailLine(
                        "Range validity — " + (entry.subScores.rangeValidity != nil
                            ? "\(dataQualityPercent(entry.subScores.rangeValidity)) of rows in range"
                            : "not scored for this metric")
                    )
                    detailLine(
                        "Trust — " + (entry.subScores.trust != nil
                            ? dataQualityPercent(entry.subScores.trust)
                            : "no trust judgement for this source")
                    )
                    detailLine("Provenance — not scored yet (see note below)")
                    if let fresh, fresh.coverageChecked, let gapCount = fresh.gapCount, gapCount > 0 {
                        let missing = fresh.totalMissingDays ?? 0
                        detailLine(
                            "\(gapCount) coverage gap\(gapCount == 1 ? "" : "s") · \(missing) missing day\(missing == 1 ? "" : "s") total"
                        )
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: JIRow<EmptyView>.minHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.metricLabel), \(dataQualitySourceDisplay(entry.source)), \(Int((entry.composite * 100).rounded())) percent, \(tone.label)")
        .accessibilityIdentifier("dataQuality.row.\(entry.id)")
    }

    @ViewBuilder
    private func freshnessLine(_ fresh: FreshnessEntry?) -> some View {
        if let fresh {
            let tone = dataQualityFreshnessTone(fresh.state)
            let stale = fresh.daysStale.map { ", \($0)d stale" } ?? ""
            let coverage = fresh.coverageChecked ? "" : " · sparse-by-design, coverage not checked"
            Text("Freshness — \(Text(tone.label).foregroundStyle(color(tone)))\(stale + coverage)")
                .font(.caption).foregroundStyle(theme.color(.muted))
        } else {
            // The hub's two reports didn't line up for this row — say so, never invent a state.
            detailLine("Freshness — —")
        }
    }

    private func detailLine(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(theme.color(.muted))
    }

    // MARK: - Source trust

    private var trustSection: some View {
        Section {
            if model.sourceTrust.isEmpty {
                Text("No source-trust rows yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
            } else {
                ForEach(model.sourceTrust) { entry in trustRow(entry) }
            }
        } header: {
            Text("Source trust · \(model.sourceTrust.count)")
                .accessibilityIdentifier("dataQuality.section.trust")
        }
    }

    private func trustRow(_ entry: SourceTrustEntry) -> some View {
        let tone = dataQualityTrustTone(entry.trustTier)
        let label = dataQualityTrustLabel(entry.trustTier)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dataQualitySourceDisplay(entry.sourceLabel)).jiFont(.footnote, weight: .bold).foregroundStyle(theme.color(.text))
                Spacer(minLength: 8)
                toneDot(tone)
                Text(label).jiFont(.caption, weight: .bold).foregroundStyle(color(tone))
            }
            Text(entry.metricClass.uppercased())
                .jiFont(.micro).foregroundStyle(theme.color(.muted))
            Text(entry.note).jiFont(.caption).foregroundStyle(theme.color(.muted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: JIRow<EmptyView>.minHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dataQualitySourceDisplay(entry.sourceLabel)), \(entry.metricClass), \(label)")
        .accessibilityIdentifier("dataQuality.trust.\(entry.id)")
    }

    // MARK: - Shared bits

    private func toneDot(_ tone: DataQualityTone) -> some View {
        Circle().fill(color(tone)).frame(width: 10, height: 10)
    }

    /// Rule 6: green is reserved for verdict/band/status — a traffic-light band is exactly that.
    private func color(_ tone: DataQualityTone) -> Color {
        switch tone {
        case .go: theme.color(.go)
        case .amber: theme.color(.reduced)
        case .red: theme.color(.danger)
        }
    }
}

/// Rule 5: what both entry points show when no `DataQualityProviding` has been installed on
/// `DataQualityAccess` (e.g. the on-device Apple Watch source, which has no hub reports) — a
/// screen that explains itself, never a blank push.
public struct DataQualityUnavailableView: View {
    @Environment(\.jiTheme) private var theme
    public init() {}
    public var body: some View {
        List {
            Section {
                ContentUnavailableView(
                    "Data quality",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Data quality reports come from the HealthTraining hub. Connect the hub in Settings › Connection to see per-source freshness, quality and trust.")
                )
            }
        }
        .jiNativeFormChrome()
        .jiTheme(.native)
        .navigationTitle("Data quality")
        .accessibilityIdentifier("dataQuality.unavailable")
    }
}
