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
// B-57 W1 r4 (fixer g3, board 5/02): a live PREVIEW card on top (your greeting in your accent, a
// link sample), then Theme, Accent colour (swatches only), Text size as a SLIDER (A … A) and the
// greeting name. "Auto" (follow iOS text size) is kept as a switch under the slider, so the
// system default stays reachable. The preview never shows a verdict or a number — it previews
// the look, not your data.

/// The slider's detents, small → extra large. "Auto" is not a size, so it is its own switch.
public nonisolated let appearanceTextSizeSteps: [FontScalePreset] = [.small, .default, .large, .xlarge]

/// The slider position of a preset; nil for Auto (the slider then sits dimmed at Default).
public nonisolated func appearanceSliderIndex(_ preset: FontScalePreset) -> Int? {
    appearanceTextSizeSteps.firstIndex(of: preset)
}

public nonisolated func appearanceThemeCaption(_ mode: ThemeMode) -> String {
    switch mode {
    case .system: "Follows your iPhone's light or dark setting."
    case .light: "Metric colours stay the same in light."
    case .dark: "Dark keeps the metric colours at full strength."
    }
}

public nonisolated let appearanceAccentCaption = "Links and the selected tab. Metric colours never change."

public struct AppearanceView: View {
    @Environment(\.jiTheme) private var theme
    @Bindable private var model: AppearanceViewModel

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

            Section("Preview") { previewCard }

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
                Text(appearanceThemeCaption(model.mode)).accessibilityIdentifier("appearance.theme.caption")
            }

            Section {
                accentRow
            } header: {
                Text("Accent colour")
            } footer: {
                Text(appearanceAccentCaption)
            }

            Section("Text size") {
                textSizeSlider
                Toggle(isOn: autoBinding) {
                    JIRow(title: "Match iPhone text size")
                }
                .tint(theme.color(.info))
                .accessibilityIdentifier("appearance.textSize.auto")
            }

            Section("Greeting") {
                HStack {
                    Text("Your name").jiFont(.body, tint: .text)
                    Spacer(minLength: 12)
                    TextField("Name", text: $model.nameDraft)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { model.commitName() }
                        .onChange(of: model.nameDraft) { _, new in
                            if new.count > ThemePrefs.maxNameLength { model.nameDraft = String(new.prefix(ThemePrefs.maxNameLength)) }
                        }
                        .accessibilityLabel("Your name")
                        .accessibilityIdentifier("appearance.name")
                }
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

    /// The board's preview: the greeting Today will show, in the chosen accent, plus a link
    /// sample — so theme, accent and text size are seen together before leaving the screen.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.previewLabel.uppercased())
                .jiFont(.footnote, weight: .bold)
                .foregroundStyle(accent)
                .accessibilityIdentifier("appearance.greetingPreview")
            Text("Today").jiFont(.title, weight: .heavy, tint: .text)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Links and the selected tab").jiFont(.subheadline, tint: .muted)
                    Spacer(minLength: 8)
                    Text("Week review").jiFont(.subheadline, weight: .semibold).foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Links and the selected tab").jiFont(.subheadline, tint: .muted)
                    Text("Week review").jiFont(.subheadline, weight: .semibold).foregroundStyle(accent)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: \(model.previewLabel), accent \(model.accentKey.label)")
        .accessibilityIdentifier("appearance.preview")
    }

    /// §8.1: the five swatches reflow into a grid rather than squeezing at AX sizes.
    private var accentRow: some View {
        Columns(minimum: 44, spacing: 12) {
            ForEach(AccentKey.allCases, id: \.self) { key in
                let selected = model.accentKey == key
                Button { model.setAccentKey(key) } label: {
                    Circle()
                        .fill(key.color(for: .native))
                        .frame(width: 36, height: 36)
                        .padding(4)
                        .overlay(Circle().strokeBorder(key.color(for: .native), lineWidth: selected ? 2 : 0))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accent: \(key.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("appearance.accent.\(key.rawValue)")
            }
        }
    }

    private var textSizeSlider: some View {
        let index = appearanceSliderIndex(model.fontScalePreset)
        return HStack(spacing: 12) {
            Text("A").jiFont(.footnote, tint: .muted).accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { Double(index ?? 1) },
                    set: { model.setFontScalePreset(appearanceTextSizeSteps[min(max(Int($0.rounded()), 0), appearanceTextSizeSteps.count - 1)]) }
                ),
                in: 0...Double(appearanceTextSizeSteps.count - 1),
                step: 1
            )
            .opacity(index == nil ? 0.45 : 1)
            .accessibilityLabel("Text size")
            .accessibilityValue(model.fontScalePreset.label)
            .accessibilityIdentifier("appearance.textSize.slider")
            Text("A").jiFont(.cardTitleLarge, tint: .muted).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }

    private var autoBinding: Binding<Bool> {
        Binding(get: { model.fontScalePreset == .system },
                set: { model.setFontScalePreset($0 ? .system : .default) })
    }

    private var themeBinding: Binding<ThemeMode> {
        Binding(get: { model.mode }, set: { model.setMode($0) })
    }
}
