import SwiftUI
import JIDesign
import JIPersistence

// W5a-L3 (P-edit-today), B-57 W1 board: page name + a SquareGrid (– hides, drag moves, Add
// restores) + "Add a square"; every tap writes through. VoiceOver keeps Move earlier/later
// actions. Pushed from `EditTodaySection` (Settings); RN's second entry (long-press on Today's header gear) has no
// Swift counterpart in `TodayGrid.swift`, so no `.navigationDestination` was added there.
public struct EditTodayView: View {
    @State private var model: EditTodayViewModel
    @State private var nameDraft = ""
    @Environment(\.jiTheme) private var theme

    public init(model: EditTodayViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                Text("Drag a square to move it. Tap – to hide it.").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("editToday.info")
                JISectionHeader("Name")
                Surface(level: 1) {
                    HStack {
                        Text("Page name").jiFont(.body).foregroundStyle(theme.color(.text))
                        Spacer()
                        TextField("Today", text: $nameDraft)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { model.setPageName(nameDraft) }
                            .accessibilityIdentifier("editToday.pageName")
                        Image(systemName: "pencil").foregroundStyle(theme.color(.info)).accessibilityHidden(true)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("On Today").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(editTodayCountText(model.prefs)).jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                }
                SquareGrid(items: editTodayVisibleItems(model.prefs, chips: model.chips), editing: true,
                           onBadge: { model.setHidden($0, hide: true) },
                           onMove: { model.moveSquare($0, before: $1) },
                           onAdd: model.prefs.hidden.first.map { first in { model.setHidden(first, hide: false) } })
                if !model.prefs.hidden.isEmpty {
                    Text("Add a square").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
                    SquareGrid(items: editTodayHiddenItems(model.prefs, chips: model.chips), onBadge: { model.setHidden($0, hide: false) })
                }
                Text("The call on top stays fixed. Hidden squares still count toward it.")
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .navigationTitle("Edit Today")
        .onAppear { model.load(); nameDraft = model.pageName }
        .onDisappear { model.setPageName(nameDraft) }
    }
}
