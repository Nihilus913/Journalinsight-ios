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
    @Bindable private var model: DataQualityViewModel

    public init(model: DataQualityViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let message): errorCard(message)
                case .empty: emptyCard
                case .loaded: content
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
        .navigationTitle("Data quality")
        .refreshable { await model.refresh() }
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Data quality").font(.largeTitle.bold()).foregroundStyle(JIColor.text)
            // Oracle `ScreenHeader info=…`, verbatim.
            Text("Per-source data quality, freshness, and trust — every source and metric the pipeline ingests, worst first.")
                .font(.subheadline).foregroundStyle(JIColor.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dataQuality.header")
    }

    private var loading: some View {
        Surface(level: 1, radius: JIRadius.card, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 260) }
        }
        .accessibilityIdentifier("dataQuality.loading")
    }

    /// Oracle's error card: its own copy plus a Retry that refetches all three reports.
    private func errorCard(_ message: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(message).foregroundStyle(JIColor.text)
                Button("Retry") { Task { await model.refresh() } }
                    .buttonStyle(.pressableScale)
                    .tint(JIColor.info)
                    .accessibilityLabel("Retry loading data quality")
                    .accessibilityIdentifier("dataQuality.retry")
            }
        }
    }

    private var emptyCard: some View {
        Surface {
            Text("No data-quality rows yet.")
                .font(.subheadline).foregroundStyle(JIColor.muted)
                .accessibilityIdentifier("dataQuality.empty")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            qualitySection
            trustSection
        }
    }

    // MARK: - Per-source quality

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Per-source quality · \(model.sortedScores.count)")
                .accessibilityIdentifier("dataQuality.section.quality")
            if model.sortedScores.isEmpty {
                Text("No data-quality rows yet.").font(.footnote).foregroundStyle(JIColor.muted)
            } else {
                ForEach(model.sortedScores) { entry in
                    qualityRow(entry, fresh: model.freshness(for: entry))
                }
            }
            if let gap = model.provenanceGap {
                Text(gap).font(.caption2).foregroundStyle(JIColor.mutedNested)
                    .accessibilityIdentifier("dataQuality.provenanceGap")
            }
        }
    }

    private func qualityRow(_ entry: QualityScoreEntry, fresh: FreshnessEntry?) -> some View {
        let tone = dataQualityCompositeTone(entry.composite)
        return Surface(level: 2, radius: JIRadius.card, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    toneDot(tone)
                    Text(entry.metricLabel).font(.footnote.bold()).foregroundStyle(JIColor.text)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text("\(Int((entry.composite * 100).rounded()))%")
                        .font(.caption.bold()).foregroundStyle(color(tone))
                }
                Text(entry.source).font(.caption2).foregroundStyle(JIColor.muted)

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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.metricLabel), \(entry.source), \(Int((entry.composite * 100).rounded())) percent, \(tone.label)")
        .accessibilityIdentifier("dataQuality.row.\(entry.id)")
    }

    @ViewBuilder
    private func freshnessLine(_ fresh: FreshnessEntry?) -> some View {
        if let fresh {
            let tone = dataQualityFreshnessTone(fresh.state)
            let stale = fresh.daysStale.map { ", \($0)d stale" } ?? ""
            let coverage = fresh.coverageChecked ? "" : " · sparse-by-design, coverage not checked"
            Text("Freshness — \(Text(tone.label).foregroundStyle(color(tone)))\(stale + coverage)")
                .font(.caption).foregroundStyle(JIColor.muted)
        } else {
            // The hub's two reports didn't line up for this row — say so, never invent a state.
            detailLine("Freshness — —")
        }
    }

    private func detailLine(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(JIColor.muted)
    }

    // MARK: - Source trust

    private var trustSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Source trust · \(model.sourceTrust.count)")
                .accessibilityIdentifier("dataQuality.section.trust")
            if model.sourceTrust.isEmpty {
                Text("No source-trust rows yet.").font(.footnote).foregroundStyle(JIColor.muted)
            } else {
                ForEach(model.sourceTrust) { entry in trustRow(entry) }
            }
        }
    }

    private func trustRow(_ entry: SourceTrustEntry) -> some View {
        let tone = dataQualityTrustTone(entry.trustTier)
        let label = dataQualityTrustLabel(entry.trustTier)
        return Surface(level: 2, radius: JIRadius.card, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.sourceLabel).font(.footnote.bold()).foregroundStyle(JIColor.text)
                    Spacer(minLength: 8)
                    toneDot(tone)
                    Text(label).font(.caption.bold()).foregroundStyle(color(tone))
                }
                Text(entry.metricClass.uppercased())
                    .font(.caption2).kerning(0.6).foregroundStyle(JIColor.muted)
                Text(entry.note).font(.caption).foregroundStyle(JIColor.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.sourceLabel), \(entry.metricClass), \(label)")
        .accessibilityIdentifier("dataQuality.trust.\(entry.id)")
    }

    // MARK: - Shared bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.bold()).kerning(0.8).foregroundStyle(JIColor.muted)
    }

    private func toneDot(_ tone: DataQualityTone) -> some View {
        Circle().fill(color(tone)).frame(width: 10, height: 10)
    }

    /// Rule 6: green is reserved for verdict/band/status — a traffic-light band is exactly that.
    private func color(_ tone: DataQualityTone) -> Color {
        switch tone {
        case .go: JIColor.go
        case .amber: JIColor.reduced
        case .red: JIColor.danger
        }
    }
}

/// Rule 5: what both entry points show when no `DataQualityProviding` has been installed on
/// `DataQualityAccess` (e.g. the on-device Apple Watch source, which has no hub reports) — a
/// screen that explains itself, never a blank push.
public struct DataQualityUnavailableView: View {
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Data quality").font(.largeTitle.bold()).foregroundStyle(JIColor.text)
                Surface {
                    Text("Data quality reports come from the HealthTraining hub. Connect the hub in Settings › Connection to see per-source freshness, quality and trust.")
                        .font(.subheadline).foregroundStyle(JIColor.muted)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
        .navigationTitle("Data quality")
        .accessibilityIdentifier("dataQuality.unavailable")
    }
}
