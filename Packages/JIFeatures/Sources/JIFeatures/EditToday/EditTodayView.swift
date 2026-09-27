import SwiftUI
import JIDesign
import JIPersistence

// W5a-L3 (P-edit-today), B-57 W1 board: page name + a SquareGrid (– hides, drag moves, Add
// restores) + "Add a square"; every tap writes through. VoiceOver keeps Move earlier/later
// actions. Pushed from `EditTodaySection` (Settings) and, since W-GUI T3, presented as a sheet
// from Day's Edit glass button (`onDone`).
public struct EditTodayView: View {
    @State private var model: EditTodayViewModel
    @State private var nameDraft = ""
    /// W-GUI T7: set when the screen is a sheet (Day's Edit button) — Done is a glass checkmark.
    private let onDone: (() -> Void)?
    @Environment(\.jiTheme) private var theme

    public init(model: EditTodayViewModel, onDone: (() -> Void)? = nil) {
        _model = State(initialValue: model); self.onDone = onDone
    }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                // W-GUI T7 (mockup 15): the page-name field is a grouped row, then "On Today · n of 8",
                // the 104 pt catalogue squares (− hides, drag moves, the dashed one adds), the caption once.
                Surface(level: 1, padding: 0) {
                    HStack(spacing: JISpacing.s3) {
                        Text("Page name").jiFont(.body).foregroundStyle(theme.color(.text))
                        Spacer(minLength: JISpacing.s2)
                        TextField("Today", text: $nameDraft)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { model.setPageName(nameDraft) }
                            .accessibilityIdentifier("editToday.pageName")
                        Image(systemName: "pencil").foregroundStyle(theme.color(.info)).accessibilityHidden(true)
                    }
                    .padding(.horizontal, JISpacing.s4)
                    .frame(minHeight: JIRowMetrics.minHeight)
                }
                HStack(alignment: .firstTextBaseline) {
                    JISectionHeader("On Today")
                    Text(editTodayCountText(model.prefs)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .padding(.trailing, JISpacing.s4)
                }
                SquareGrid(items: editTodayVisibleItems(model.prefs, chips: model.chips), editing: true, family: squareTileFamily(catalog: true),
                           onBadge: { model.setHidden($0, hide: true) },
                           onMove: { model.moveSquare($0, before: $1) },
                           onAdd: { model.openAddCatalogue() })
                if !model.prefs.hidden.isEmpty {
                    JISectionHeader("Not on Today")
                    SquareGrid(items: editTodayHiddenItems(model.prefs, chips: model.chips), family: squareTileFamily(catalog: true),
                               onBadge: { model.setHidden($0, hide: false) })
                }
                Text(editTodayCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s4)
                    .accessibilityIdentifier("editToday.info")
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.vertical, JISpacing.s3)
            .readableColumn()
        }
        .jiPageGround()
        .navigationTitle("Edit Today")
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    JIGlassButton("checkmark", label: "Done", action: onDone).accessibilityIdentifier("editToday.done")
                }
            }
        }
        .sheet(isPresented: $model.showsAddCatalogue) { catalogue }
        .onAppear { model.load(); nameDraft = model.pageName }
        .onDisappear { model.setPageName(nameDraft) }
    }

    /// W-FIX2 BUG-20: board 04's "Add a square" catalogue — every tap writes through like the rest
    /// of this screen. W-GUI T7 (mockup 16): one row per square with a tick circle.
    private var catalogue: some View {
        NavigationStack {
            ScreenScroll {
                VStack(alignment: .leading, spacing: 0) {
                    let items = editTodayCatalogueItems(model.prefs, chips: model.chips)
                    JISectionHeader("Not on Today")
                    Surface(level: 1, padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { JIRowDivider() }
                                catalogueRow(item)
                            }
                        }
                        .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
                    }
                    Text(editTodayCatalogueCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s4)
                }
                .padding(.horizontal, JISpacing.sideMargin).padding(.vertical, JISpacing.s3)
                .readableColumn()
            }
            .jiPageGround()
            .navigationTitle("Add a square")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.showsAddCatalogue = false }.accessibilityIdentifier("editToday.catalogue.done")
                }
            }
        }
        .accessibilityIdentifier("editToday.catalogue")
        .jiSheetGround()
    }

    private func catalogueRow(_ item: JISquareItem) -> some View {
        let on = editTodayCatalogueRowIsOn(item)
        return Button { model.toggleFromCatalogue(item.id) } label: {
            HStack(spacing: JISpacing.s3) {
                if let symbol = item.systemImage {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.color(item.tint))
                        .frame(width: JIRowMetrics.iconWell, height: JIRowMetrics.iconWell)
                        .background(theme.color(item.tint).opacity(0.16), in: RoundedRectangle(cornerRadius: JIRowMetrics.iconWellRadius, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(editTodayCatalogueRowText(item)).jiFont(.body).foregroundStyle(theme.color(.text))
                    .lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: JISpacing.s2)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? theme.color(.info) : theme.color(.mutedNested))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, JIRowMetrics.verticalPadding)
            .frame(minHeight: JIRowMetrics.minHeight - 2 * JIRowMetrics.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel(editTodayCatalogueRowText(item))
        .accessibilityValue(on ? "On Today" : "Not on Today")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("editToday.catalogue.\(item.id)")
    }
}

// MARK: - W-GUI T7 (mockups 15 / 16) copy, pure

public nonisolated let editTodayCaption = "Drag a square to move it. Tap − to hide it. The call on top stays fixed; hidden squares still count toward it. Today holds \(KpiSelection.minSelected) to \(KpiSelection.maxSelected) squares, the same set as My KPIs."
public nonisolated let editTodayCatalogueCaption = "Tick to add. Squares keep their size; the grid stays three wide."

/// "Calories · 1183 kcal" — the label with the square's current value, or its reason word.
public nonisolated func editTodayCatalogueRowText(_ item: JISquareItem) -> String {
    if let v = item.value {
        let unit = item.unit.map { $0.isEmpty ? "" : " \($0)" } ?? ""
        return "\(item.label) · \(jiNumber(v, item.decimals))\(unit)"
    }
    return "\(item.label) · \(item.status?.word ?? JIMissingReason.noData.rawValue)"
}

/// A ticked row is a square already on Today (`.selected`); `.add` is off.
public nonisolated func editTodayCatalogueRowIsOn(_ item: JISquareItem) -> Bool { item.badge == .selected }
