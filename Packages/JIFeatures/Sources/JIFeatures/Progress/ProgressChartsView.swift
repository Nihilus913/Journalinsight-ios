import SwiftUI
import JICore
import JIDesign

/// B-94 b94p4 (Bevel BP-4, mockup docs/waves/mockups/bevel/BP-4.html) — Training › Progress:
/// Strength + Cardio chart cards (TrendChart), a per-chart menu (Pin / Unpin / Hide), and the
/// Edit sheet (pin, reorder, hide). Named `ProgressChartsView` so it never shadows SwiftUI's
/// `ProgressView`.
public struct ProgressChartsView: View {
    @Bindable private var model: ProgressViewModel
    @State private var editing = false
    private let theme = JITheme.native

    public init(model: ProgressViewModel) { self.model = model }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("progress.subtitle")
                if let offline = model.offlineText {
                    Text(offline).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("progress.offline")
                }
                section("Strength", cards: model.strengthCards, error: model.strengthError,
                        empty: "Not enough data yet. Strength charts appear after 3 logged sessions of a lift.")
                section("Cardio", cards: model.cardioCards, error: model.cardioError, empty: nil)
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiTheme(.native)
        .navigationTitle("Progress")
        .accessibilityIdentifier("progress.screen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
                    .accessibilityIdentifier("progress.edit")
            }
        }
        .sheet(isPresented: $editing) { ProgressEditSheet(model: model) }
        .refreshable { await model.load() }
        .task { await model.load() }
        #if DEBUG
        // B-94 dev affordance: `-progress-edit` opens the Edit sheet once loaded (sim screenshots);
        // `-progress-range <D|W|M|6M|Y>` starts at that range.
        .task {
            if let i = CommandLine.arguments.firstIndex(of: "-progress-range"), i + 1 < CommandLine.arguments.count,
               let r = TrendRange(rawValue: CommandLine.arguments[i + 1]) { model.range = r }
            // `-progress-reset` clears every pin / hide first (a clean default screenshot).
            if CommandLine.arguments.contains("-progress-reset") { model.resetPrefs() }
            // `-progress-pin <id,id,…>` pins those charts in that order, as the menu's Pin does
            // (written through to PrefStore — a later launch without it shows the order persisted).
            if let i = CommandLine.arguments.firstIndex(of: "-progress-pin"), i + 1 < CommandLine.arguments.count {
                for raw in CommandLine.arguments[i + 1].split(separator: ",") {
                    if let id = ProgressChartID(rawValue: String(raw)) { model.pin(id) }
                }
            }
            guard CommandLine.arguments.contains("-progress-edit") else { return }
            try? await Task.sleep(for: .seconds(2))
            editing = true
        }
        #endif
    }

    @ViewBuilder
    private func section(_ title: String, cards: [ProgressCard], error: String?, empty: String?) -> some View {
        JISectionHeader(title)
        VStack(alignment: .leading, spacing: 12) {
            if let error {
                Text("Showing what this phone has — \(error)").jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if cards.isEmpty, let empty {
                Surface(level: 1, padding: JISpacing.cardPadding) {
                    Text(model.loading ? "Loading…" : empty).jiFont(.body).foregroundStyle(theme.color(.muted))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("progress.\(title.lowercased()).empty")
            }
            ForEach(cards) { card in
                ProgressChartCard(card: card, range: $model.range,
                                  onPin: { model.togglePin(card.id) }, onHide: { model.setHidden(card.id, true) })
            }
        }
    }
}

/// One chart card: title + "⋯" menu, headline value, TrendChart (or the thin state), caption.
struct ProgressChartCard: View {
    let card: ProgressCard
    @Binding var range: TrendRange
    let onPin: () -> Void
    let onHide: () -> Void
    private let theme = JITheme.native

    var body: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    if card.pinned {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(theme.color(.info))
                            .accessibilityLabel("Pinned")
                    }
                    Text(card.title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Menu {
                        Button(card.pinned ? "Unpin" : "Pin", systemImage: card.pinned ? "pin.slash" : "pin", action: onPin)
                            .accessibilityIdentifier("progress.menu.pin")
                        Button("Hide", systemImage: "eye.slash", role: .destructive, action: onHide)
                            .accessibilityIdentifier("progress.menu.hide")
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.bold)).foregroundStyle(theme.color(.muted))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Chart options")
                    .accessibilityIdentifier("progress.menu.\(card.id.rawValue)")
                }
                if let headline = card.headline {
                    Text(headline).jiFont(.numeralSmall, design: .rounded).foregroundStyle(theme.color(.text))
                        .monospacedDigit().lineLimit(1).fixedSize()
                        .accessibilityIdentifier("progress.headline.\(card.id.rawValue)")
                }
                if card.thin {
                    VStack(alignment: .leading, spacing: 10) {
                        rangePicker
                        VStack(spacing: 4) {
                            Text("Not enough data yet").jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                            Text("\(card.count) of \(ProgressViewModel.minPoints) in this range")
                                .jiFont(.caption).foregroundStyle(theme.color(.muted))
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("progress.thin.\(card.id.rawValue)")
                    }
                } else {
                    TrendChart(points: card.points, tint: theme.color(.text), unit: card.unit.isEmpty ? nil : card.unit,
                               range: $range, showAll: nil, kind: card.kind, series: card.series,
                               valueFormat: ProgressFormat.chartValueFormat(card.id))
                }
                Text(card.caption).jiFont(.micro).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("progress.card.\(card.id.rawValue)")
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// Edit sheet: Pinned (drag to reorder, unpin), Shown (pin, hide), Hidden (show again).
struct ProgressEditSheet: View {
    @Bindable var model: ProgressViewModel
    @Environment(\.dismiss) private var dismiss
    private let theme = JITheme.native

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.prefs.pinned.isEmpty {
                        Text("Nothing pinned. Pin a chart to keep it at the top.").foregroundStyle(.secondary)
                    }
                    ForEach(model.prefs.pinned, id: \.self) { id in
                        HStack {
                            Button { model.unpin(id) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Unpin \(ProgressFormat.title(id))")
                            Text(ProgressFormat.title(id))
                        }
                        .accessibilityIdentifier("progress.edit.pinned.\(id.rawValue)")
                    }
                    .onMove { model.movePins(fromOffsets: $0, toOffset: $1) }
                } header: { Text("Pinned") }

                Section {
                    ForEach(model.catalogue.filter { !model.prefs.pinned.contains($0) && !model.isHidden($0) }, id: \.self) { id in
                        HStack {
                            Button { model.pin(id) } label: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(theme.color(.info))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Pin \(ProgressFormat.title(id))")
                            .accessibilityIdentifier("progress.edit.pin.\(id.rawValue)")
                            Text(ProgressFormat.title(id))
                            Spacer()
                            Button("Hide") { model.setHidden(id, true) }.buttonStyle(.borderless).font(.footnote)
                        }
                    }
                } header: { Text("Charts") }

                if !model.prefs.hidden.isEmpty {
                    Section {
                        ForEach(model.prefs.hidden, id: \.self) { id in
                            HStack {
                                Text(ProgressFormat.title(id)).foregroundStyle(.secondary)
                                Spacer()
                                Button("Show") { model.setHidden(id, false) }.buttonStyle(.borderless).font(.footnote)
                            }
                        }
                    } header: { Text("Hidden") }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit charts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("progress.edit.done")
                }
            }
            .accessibilityIdentifier("progress.edit.sheet")
        }
        .presentationDetents([.large])
    }
}
