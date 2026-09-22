import SwiftUI
import JIDesign
import JIPersistence

// W5a-L3 (P-edit-today). Port of `mobile/app/edit-today.tsx`: header copy, one row per tile
// (label · up · down · eye), hidden rows dimmed to 0.45, every tap writes through. Pushed from
// `EditTodaySection` (Settings); RN's second entry (long-press on Today's header gear) has no
// Swift counterpart in `TodayGrid.swift`, so no `.navigationDestination` was added there.
public struct EditTodayView: View {
    @State private var model: EditTodayViewModel
    @Environment(\.jiTheme) private var theme

    public init(model: EditTodayViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        Form {
            Section {
                Text("Choose which tiles show on Today. Prefer dragging tiles directly on Today itself — long-press one to reorder in place. The up/down arrows below are a screen-reader friendly fallback for the same reorder. The verdict card always leads — it isn't part of this list.")
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("editToday.info")
            }
            Section("Tiles") {
                ForEach(Array(model.prefs.order.enumerated()), id: \.element) { index, id in
                    tileRow(id: id, index: index, count: model.prefs.order.count)
                }
            }
        }
        // §5: the grouped background and inset-grouped cells come from the system.
        .jiNativeFormChrome()   // `.insetGrouped` on iOS, no-op on the macOS test host
        .navigationTitle("Edit Today")
        .onAppear { model.load() }
    }

    @ViewBuilder
    private func tileRow(id: String, index: Int, count: Int) -> some View {
        let label = TodayTileRegistry.label(for: id)
        let hidden = model.isHidden(id)
        let atTop = index == 0
        let atBottom = index == count - 1
        HStack(spacing: 8) {
            Text(label).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.text))
            Spacer(minLength: 8)
            circleButton(systemImage: "chevron.up", tint: atTop ? theme.color(.muted) : theme.color(.text), disabled: atTop) {
                model.move(id, direction: -1)
            }
            .accessibilityLabel("Move \(label) up")
            .accessibilityIdentifier("editToday.\(id).up")
            circleButton(systemImage: "chevron.down", tint: atBottom ? theme.color(.muted) : theme.color(.text), disabled: atBottom) {
                model.move(id, direction: 1)
            }
            .accessibilityLabel("Move \(label) down")
            .accessibilityIdentifier("editToday.\(id).down")
            circleButton(systemImage: hidden ? "eye.slash" : "eye", tint: hidden ? theme.color(.muted) : theme.color(.info), disabled: false) {
                model.setHidden(id, hide: !hidden)
            }
            .accessibilityLabel(hidden ? "Show \(label) on Today" : "Hide \(label) from Today")
            .accessibilityIdentifier("editToday.\(id).toggle")
        }
        .frame(minHeight: JIRow<EmptyView>.minHeight)   // §2b.2: the inset-grouped row height
        .opacity(hidden ? 0.45 : 1)
        .accessibilityIdentifier("editToday.row.\(id)")
    }

    /// RN `circleBtnStyle` + `PressableScale variant="stepper"`; disabled dimming is the button
    /// style's job (rule 7 press-in scale via `.pressableScale`).
    private func circleButton(systemImage: String, tint: Color, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .jiFont(.body, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(theme.color(.surface2), in: Circle())
        }
        .buttonStyle(.pressableScale)
        .disabled(disabled)
    }
}
