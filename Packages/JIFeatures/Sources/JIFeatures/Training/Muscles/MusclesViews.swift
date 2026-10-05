import SwiftUI
import JICompute
import JIDesign

/// B-90 p5 — freshness colours in `SignalStatus` roles only (mockup BP-2-3): Recovered → go,
/// Fatigued → reduced, Depleted → danger, Calibrating / No data → muted. Load stays the `.load`
/// violet metric colour (never a verdict colour).
extension MuscleState {
    var role: JIColorRole {
        switch self {
        case .recovered: .go
        case .fatigued: .reduced
        case .depleted: .danger
        case .calibrating, .noData: .muted
        }
    }
}

@MainActor
func musclesMapFills(_ s: MusclesSummary, _ theme: JITheme) -> [Muscle: Color] {
    var out: [Muscle: Color] = [:]
    for (m, state) in s.mapStates {
        switch (s.phase, state) {
        case (.calibrating, _), (_, .calibrating): out[m] = theme.color(.load).opacity(0.45)   // flat violet wash, no state colour
        case (_, .noData): continue
        default: out[m] = theme.color(state.role).opacity(0.85)
        }
    }
    return out
}

struct MusclesStatusChip: View {
    let state: MuscleState
    @Environment(\.jiTheme) private var theme
    var body: some View {
        Text(state.word).jiFont(.caption, weight: .semibold)
            .foregroundStyle(theme.color(state.role))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(theme.color(state.role).opacity(0.16)))
            .overlay(Capsule().strokeBorder(theme.color(state.role).opacity(state.role == .muted ? 0.5 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .lineLimit(1).fixedSize()
    }
}

struct MusclesMapPair: View {
    let summary: MusclesSummary
    var height: CGFloat
    @Environment(\.jiTheme) private var theme
    var body: some View {
        let fills = musclesMapFills(summary, theme)
        HStack(spacing: 4) {
            ForEach(MuscleBodySide.allCases) { side in MuscleBodyView(side: side, fills: fills) }
        }
        .frame(height: height)
    }
}

/// A 3-segment calibration bar.
struct MusclesCalibrationBar: View {
    let progress: Int
    @Environment(\.jiTheme) private var theme
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<MuscleFreshness.calibrationWorkouts, id: \.self) { i in
                Capsule().fill(i < progress ? theme.color(.load) : theme.color(.muted).opacity(0.25)).frame(height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Training tab card

struct MusclesCard: View {
    let summary: MusclesSummary
    let calendar: Calendar
    let onOpen: () -> Void
    @Environment(\.jiTheme) private var theme

    private var tint: Color? {
        guard summary.phase == .populated, let worst = summary.rows.first?.state, worst.role != .muted else { return nil }
        return theme.color(worst.role)
    }

    var body: some View {
        Group {
            if summary.phase == .empty {
                content
            } else {
                Button(action: onOpen) { content }.buttonStyle(.pressableScale)
                    .accessibilityHint("Opens the per-muscle freshness and load")
            }
        }
        .accessibilityIdentifier("training-muscles-card")
    }

    private var content: some View {
        Surface(level: 1, padding: JISpacing.cardPadding, tint: tint) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Muscles").jiFont(.cardTitle).foregroundStyle(theme.color(.text))
                    Text("est.").jiFont(.caption).foregroundStyle(theme.color(.muted))
                    Spacer(minLength: 0)
                    if summary.phase != .empty {
                        Image(systemName: "chevron.right").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    }
                }
                HStack(alignment: .center, spacing: JISpacing.s3) {
                    MusclesMapPair(summary: summary, height: 112).frame(width: 110)
                    VStack(alignment: .leading, spacing: JISpacing.s2) { lines }
                    Spacer(minLength: 0)
                }
                if let last = MusclesText.lastLine(summary, calendar) {
                    Text(last).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("muscles-card-last")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var lines: some View {
        switch summary.phase {
        case .empty:
            Text("Log a strength session to see how fresh each muscle is.").jiFont(.bodySmall).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("muscles-card-empty")
        case .calibrating:
            Text("Calibrating").jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
            MusclesCalibrationBar(progress: summary.calibrationProgress).frame(maxWidth: 140)
            Text(MusclesText.calibrationLine(summary)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                .lineLimit(1).fixedSize()
                .accessibilityIdentifier("muscles-card-calibrating")
        case .populated:
            ForEach([MuscleState.depleted, .fatigued, .recovered], id: \.rank) { state in
                if let names = MusclesText.names(summary.rows.filter { $0.state == state }) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.word).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(state.role))
                        Text(names).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text)).lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Pushed screen

struct MusclesScreen: View {
    @Bindable var model: MusclesModel
    @State private var detail: Muscle?
    @State private var showHow = false
    @Environment(\.jiTheme) private var theme
    private var initialDetail: Muscle?

    init(model: MusclesModel, initialDetail: Muscle? = nil) {
        self.model = model; self.initialDetail = initialDetail
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let s = model.summary {
                    hero(s)
                    JISectionHeader(s.phase == .populated ? "By muscle · load 7 d / 28 d" : "By muscle")
                    list(s)
                    howRow
                } else {
                    Surface { SkeletonBlock(height: 220) }
                }
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .navigationTitle("Muscles")
        .onAppear { model.reload() }
        .task {
            if let initialDetail { try? await Task.sleep(for: .seconds(1)); detail = initialDetail }
        }
        .sheet(item: Binding(get: { detail.map(MuscleRef.init) }, set: { detail = $0?.muscle })) { ref in
            if let s = model.summary, let row = s.row(ref.muscle) {
                MuscleDetailSheet(row: row, calendar: model.calendar)
            }
        }
        .sheet(isPresented: $showHow) {
            NavigationStack {
                ScrollView {
                    HowWeCalculate(title: "Muscles", steps: MusclesText.howSteps.map { HowWeCalculateStep(title: $0.0, body: $0.1) },
                                   note: "Estimates, not a measurement. Thresholds are our own heuristics.")
                        .padding(JISpacing.sideMargin)
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { showHow = false } } }
            }
        }
        .accessibilityIdentifier("muscles-screen")
    }

    private func hero(_ s: MusclesSummary) -> some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                HStack {
                    Text("Freshness").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    Spacer()
                    Text("est. · \(MusclesText.dayTime(s.asOf, model.calendar))").jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                Text(MusclesText.headline(s)).jiFont(.cardTitleLarge).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("muscles-headline")
                if let last = MusclesText.lastLine(s, model.calendar) {
                    Text(last).jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("muscles-last")
                }
                switch s.phase {
                case .calibrating:
                    MusclesCalibrationBar(progress: s.calibrationProgress)
                    Text(MusclesText.calibrationLine(s)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .lineLimit(1).fixedSize()
                        .accessibilityIdentifier("muscles-calibrating")
                case .empty:
                    Text("Log a strength session (Training → Start session → Log sets) and each muscle you train shows up here.")
                        .jiFont(.bodySmall).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("muscles-empty")
                case .populated:
                    legend
                }
                MusclesMapPair(summary: s, height: 230).frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: JISpacing.s3) {
            ForEach([MuscleState.recovered, .fatigued, .depleted, .calibrating(0)], id: \.rank) { st in
                HStack(spacing: 4) {
                    Circle().fill(st.role == .muted ? theme.color(.load).opacity(0.45) : theme.color(st.role)).frame(width: 8, height: 8)
                    Text(st.word).jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1).fixedSize()
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func list(_ s: MusclesSummary) -> some View {
        Surface(level: 1, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(s.rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { JIRowDivider() }
                    Button { if row.state != .noData { detail = row.muscle } } label: { rowView(row) }
                        .buttonStyle(.plain)
                        .disabled(row.state == .noData)
                        .accessibilityIdentifier("muscles-row-\(row.muscle.rawValue)")
                }
            }
            .padding(.horizontal, JISpacing.s4).padding(.vertical, 4)
        }
    }

    private func rowView(_ row: MuscleRowSummary) -> some View {
        HStack(alignment: .center, spacing: JISpacing.s3) {
            Circle().fill(row.state.role == .muted ? Color.clear : theme.color(row.state.role)).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(theme.color(.muted), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .opacity(row.state.role == .muted ? 1 : 0))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text)).lineLimit(1)
                Text(MusclesText.rowDetail(row, model.calendar)).jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: JISpacing.s2)
            VStack(alignment: .trailing, spacing: 2) {
                MusclesStatusChip(state: row.state)
                Text(MusclesText.ratio(row)).jiFont(.caption, weight: .semibold)
                    .foregroundStyle(row.ratio == nil ? theme.color(.muted) : theme.color(.load)).lineLimit(1).fixedSize()
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var howRow: some View {
        Surface(level: 1, padding: 0) {
            Button { showHow = true } label: {
                JIChevronRow(title: "How we calculate", value: "Estimates", systemImage: "function")
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, JIChevronRowMetrics.verticalPadding)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, JISpacing.s4)
        .accessibilityIdentifier("muscles-how")
    }
}

private struct MuscleRef: Identifiable { let muscle: Muscle; var id: String { muscle.rawValue } }

// MARK: - Detail sheet

struct MuscleDetailSheet: View {
    let row: MuscleRowSummary
    let calendar: Calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.jiTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JISpacing.s4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name).jiFont(.title).foregroundStyle(theme.color(.text))
                        Spacer()
                        MusclesStatusChip(state: row.state)
                    }
                    if let line = trainedLine {
                        Text(line).jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1).minimumScaleFactor(0.8)
                            .accessibilityIdentifier("muscle-detail-trained")
                    }
                    facts
                    loadCard
                    if !row.counted.isEmpty { countedCard }
                    Text("Estimates. Load = reps × kg (bodyweight sets 0.65 × your weight). Not a measurement.")
                        .jiFont(.caption).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(JISpacing.sideMargin)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
        }
        .jiTheme(.native)
        .presentationDetents([.large])
        .accessibilityIdentifier("muscle-detail-sheet")
    }

    private var trainedLine: String? {
        guard let at = row.lastAt else { return nil }
        var parts = ["Trained \(MusclesText.ago(row.hoursSince ?? 0))", MusclesText.dayTime(at, calendar)]
        if let n = row.lastSessionName { parts.append(n) }
        if let l = row.lastLoad { parts.append("\(MusclesText.load(l)) load") }
        return parts.joined(separator: " · ")
    }

    private var facts: some View {
        HStack(spacing: JISpacing.s3) {
            fact(title: "Fresh by (est.) · \(row.aboveP75 ? "72" : "48") h rule",
                 value: row.freshBy.map { "~" + MusclesText.dayTime($0, calendar) } ?? (row.state == .recovered ? "Now" : "—"))
            fact(title: "Last vs median\(row.aboveP75 ? " · >P75" : "")",
                 value: { if let l = row.lastLoad, let m = row.medianLoad { "\(MusclesText.load(l)) vs \(MusclesText.load(m))" } else { "—" } }())
        }
    }

    private func fact(title: String, value: String) -> some View {
        Surface(level: 2, padding: JISpacing.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).jiFont(.caption).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
                Text(value).jiFont(.numeralSmall).foregroundStyle(theme.color(.text)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        }
    }

    private var loadCard: some View {
        Surface(level: 2, padding: JISpacing.s3) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                HStack {
                    Text("Load · 7 vs 28 days").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.text))
                    Spacer()
                    Text("reps × kg").jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                bar("This week", row.acute, opacity: 1)
                bar("28-day pace / week", row.chronic, opacity: 0.45)
                if let r = row.ratio, let word = row.bandWord {
                    HStack(spacing: JISpacing.s2) {
                        Text(musclesNumber(r, 2)).jiFont(.numeralSmall).foregroundStyle(theme.color(.load))
                        Text(word).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    }
                    Text("Bands 0.8–1.3 productive, as for whole-body load.").jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Ratio after 28 days of history.").jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(_ title: String, _ v: Double, opacity: Double) -> some View {
        let maxV = max(row.acute, row.chronic, 1)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).jiFont(.caption).foregroundStyle(theme.color(.muted))
                Spacer()
                Text(v > 0 ? MusclesText.load(v) : "—").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.text))
            }
            GeometryReader { g in
                Capsule().fill(theme.color(.muted).opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(theme.color(.load).opacity(opacity)).frame(width: max(4, g.size.width * v / maxV))
                    }
            }
            .frame(height: 8)
        }
    }

    private var countedCard: some View {
        Surface(level: 2, padding: JISpacing.s3) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                Text("What counted · 7 d").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.text))
                ForEach(row.counted) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.exercise).jiFont(.bodySmall).foregroundStyle(theme.color(.text)).lineLimit(1)
                            Text(c.creditLine).jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1)
                        }
                        Spacer()
                        Text(MusclesText.load(c.load)).jiFont(.bodySmall, weight: .semibold).foregroundStyle(theme.color(.text))
                    }
                }
            }
        }
    }
}
