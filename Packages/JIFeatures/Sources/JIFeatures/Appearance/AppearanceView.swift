import SwiftUI
import JIDesign

/// W5a-L1 (P-appearance), mirrors `mobile/app/appearance.tsx`. B-33 §5: the four hand-drawn
/// `SectionCard`s become real inset-grouped `List` sections, the explicit page background is
/// gone (the system grouped background shows through), and the pills that used to be tinted
/// rectangles are the system's own controls — a segmented `Picker` for theme mode and text size,
/// a row of accent swatches, a plain `TextField` row for the greeting name.
/// `.preferredColorScheme` here still previews the choice inside this presentation; the app root
/// applies the same `ThemeMode.preferredColorScheme` globally.
/// "Color source" (Android Material You) has no iOS equivalent and is descoped; the pref persists.
public struct AppearanceView: View {
    @Environment(\.jiTheme) private var theme
    @Bindable private var model: AppearanceViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AppearanceViewModel) { self.model = model }

    private var accent: Color { model.accentKey.color(for: .native) }

    public var body: some View {
        List {
            if let error = model.saveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.color(.danger))
                        .accessibilityIdentifier("appearance.saveError")
                }
            }

            Section {
                Picker("Theme", selection: themeBinding) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode).accessibilityIdentifier("appearance.mode.\(mode.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Theme")
            } header: {
                Text("Theme")
            } footer: {
                Text("Theme, accent color, text size, and the name used in Today's greeting — all local to this device.")
            }

            Section("Accent color") { accentRow }

            Section("Text size") {
                Picker("Text size", selection: fontScaleBinding) {
                    ForEach(FontScalePreset.allCases, id: \.self) { preset in
                        Text(preset.label).tag(preset).accessibilityIdentifier("appearance.textSize.\(preset.rawValue)")
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                TextField("Your name", text: $model.nameDraft)
                    .onSubmit { model.commitName() }
                    .onChange(of: model.nameDraft) { _, new in
                        if new.count > ThemePrefs.maxNameLength { model.nameDraft = String(new.prefix(ThemePrefs.maxNameLength)) }
                    }
                    .accessibilityLabel("Your name")
                    .accessibilityIdentifier("appearance.name")
                JIRow(title: "Today will show") { Text(model.previewLabel) }
                    .accessibilityIdentifier("appearance.greetingPreview")
            } header: {
                Text("Greeting")
            }

            Section {
                Button("Done") {
                    model.commitName()
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Done")
                .accessibilityIdentifier("appearance.done")
            }
        }
        .jiNativeFormChrome()
        .readableColumn()
        .jiTheme(.native)
        .tint(accent)
        .navigationTitle("Appearance")
        .preferredColorScheme(model.preferredColorScheme)
        .dynamicTypeSize(model.dynamicTypeSize.map { $0...$0 } ?? DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5)
        .onDisappear { model.commitName() }
    }

    /// §8.1: the five swatches reflow into a grid rather than squeezing at AX sizes.
    private var accentRow: some View {
        Columns(minimum: 56, spacing: 12) {
            ForEach(AccentKey.allCases, id: \.self) { key in
                let selected = model.accentKey == key
                Button { model.setAccentKey(key) } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(key.color(for: .native))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(theme.color(.text), lineWidth: selected ? 3 : 0))
                        Text(key.label).jiFont(.caption).foregroundStyle(theme.color(.muted))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accent: \(key.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("appearance.accent.\(key.rawValue)")
            }
        }
    }

    private var themeBinding: Binding<ThemeMode> {
        Binding(get: { model.mode }, set: { model.setMode($0) })
    }

    private var fontScaleBinding: Binding<FontScalePreset> {
        Binding(get: { model.fontScalePreset }, set: { model.setFontScalePreset($0) })
    }
}
