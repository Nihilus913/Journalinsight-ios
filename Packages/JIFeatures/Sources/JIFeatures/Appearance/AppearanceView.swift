import SwiftUI
import JIDesign

/// W5a-L1 (P-appearance), mirrors `mobile/app/appearance.tsx`: Theme / Accent color / Text size /
/// Greeting cards, each a row of selectable pills (RN `PressableScale variant="row"`), the selected
/// one filled with `uiAccent`. Every colour is a `JIColor` neutral, so the screen re-renders in the
/// mode being picked, live — `.preferredColorScheme` here previews the choice inside this
/// presentation; the app root applies the same `ThemeMode.preferredColorScheme` globally.
/// "Color source" (Android Material You) has no iOS equivalent and is descoped; the pref persists.
public struct AppearanceView: View {
    @Bindable private var model: AppearanceViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AppearanceViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Theme, accent color, text size, and the name used in Today's greeting — all local to this device.")
                    .font(.footnote).foregroundStyle(JIColor.muted)
                if let error = model.saveError {
                    Text(error).font(.footnote).foregroundStyle(JIColor.danger)
                        .accessibilityIdentifier("appearance.saveError")
                }
                themeCard
                accentCard
                textSizeCard
                greetingCard
                Button("Done") {
                    model.commitName()
                    dismiss()
                }
                .buttonStyle(.pressableScale)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(JIColor.info, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(JIColor.fixed(\.bg, for: .dark))
                .accessibilityLabel("Done")
                .accessibilityIdentifier("appearance.done")
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(JIColor.bg)
        .navigationTitle("Appearance")
        .preferredColorScheme(model.preferredColorScheme)
        .dynamicTypeSize(model.dynamicTypeSize.map { $0...$0 } ?? DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5)
        .onDisappear { model.commitName() }
    }

    // MARK: Cards (RN `SectionCard`)

    private func card<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        Surface(level: 1, radius: JIRadius.card, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(label.uppercased()).font(.caption2.weight(.bold)).kerning(1).foregroundStyle(JIColor.muted)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var themeCard: some View {
        card("Theme") {
            HStack(spacing: 8) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    pill(mode.label, selected: model.mode == mode, fill: true) { model.setMode(mode) }
                        .accessibilityLabel("Theme: \(mode.label)")
                        .accessibilityIdentifier("appearance.mode.\(mode.rawValue)")
                }
            }
        }
    }

    private var accentCard: some View {
        card("Accent color") {
            HStack(spacing: 14) {
                ForEach(AccentKey.allCases, id: \.self) { key in
                    let selected = model.accentKey == key
                    Button { model.setAccentKey(key) } label: {
                        Circle()
                            .fill(key.color)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(JIColor.text, lineWidth: selected ? 3 : 0))
                    }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Accent: \(key.label)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("appearance.accent.\(key.rawValue)")
                }
            }
        }
    }

    private var textSizeCard: some View {
        card("Text size") {
            FlowRow(spacing: 8) {
                ForEach(FontScalePreset.allCases, id: \.self) { preset in
                    pill(preset.label, selected: model.fontScalePreset == preset, fill: false) { model.setFontScalePreset(preset) }
                        .accessibilityLabel("Text size: \(preset.label)")
                        .accessibilityIdentifier("appearance.textSize.\(preset.rawValue)")
                }
            }
        }
    }

    private var greetingCard: some View {
        card("Greeting") {
            TextField("Your name", text: $model.nameDraft)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(JIColor.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(JIColor.text)
                .onSubmit { model.commitName() }
                .onChange(of: model.nameDraft) { _, new in
                    if new.count > ThemePrefs.maxNameLength { model.nameDraft = String(new.prefix(ThemePrefs.maxNameLength)) }
                }
                .accessibilityLabel("Your name")
                .accessibilityIdentifier("appearance.name")
            (Text("Today will show: ").foregroundStyle(JIColor.muted)
                + Text(model.previewLabel).foregroundStyle(JIColor.text).fontWeight(.semibold))
                .font(.footnote)
                .accessibilityIdentifier("appearance.greetingPreview")
        }
    }

    /// RN pill: selected = `uiAccent` fill with `bg`-coloured text; otherwise `surface2` + `text`.
    private func pill(_ label: String, selected: Bool, fill: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(fill ? .bold : .semibold))
                .foregroundStyle(selected ? JIColor.bg : JIColor.text)
                .padding(.vertical, fill ? 10 : 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: fill ? .infinity : nil)
                .background(selected ? model.uiAccent : JIColor.surface2, in: RoundedRectangle(cornerRadius: fill ? 12 : 10, style: .continuous))
        }
        .buttonStyle(.pressableScale)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// RN `flexWrap: "wrap"` row for the five text-size pills.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return place(in: width, subviews: subviews, commit: nil)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = place(in: bounds.width, subviews: subviews, commit: bounds.origin)
    }

    private func place(in width: CGFloat, subviews: Subviews, commit origin: CGPoint?) -> CGSize {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            if let origin { view.place(at: CGPoint(x: origin.x + x, y: origin.y + y), proposal: .unspecified) }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }
}
