import SwiftUI

/// W-GUI F9 — report §4.5 "Row": the inset-grouped disclosure row every More / Settings /
/// "How the morning call works" entry is drawn as. 56 pt minimum, 12 pt vertical padding, a
/// 32 pt icon well with a 10 pt radius, primary title, muted trailing value, disclosure chevron
/// (report §7 rule 2: a row with a chevron, never a text link). Promoted from
/// `App/RootTabView.swift`'s `MoreChevronRow` (W-FIX2 BUG-47) so every screen shares one row.
public nonisolated enum JIChevronRowMetrics {
    public static let minHeight: CGFloat = JITileHeight.row.base
    public static let verticalPadding: CGFloat = JISpacing.s3
    public static let iconWell: CGFloat = 32
    public static let iconWellRadius: CGFloat = 10
    public static let chevron = "chevron.right"
    /// W-FIX6 F6-6: one line up to xxxLarge; at accessibility sizes the title wraps ("How the
    /// morni…" at AX3 was `lineLimit(1)`).
    public static func titleLineLimit(_ size: DynamicTypeSize) -> Int? { size.isAccessibilitySize ? nil : 1 }
    /// At accessibility sizes the muted value drops under the title instead of squeezing it.
    public static func stacksValue(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
}

public struct JIChevronRow<Label: View>: View {
    @ViewBuilder let label: () -> Label
    @Environment(\.jiTheme) private var theme

    public init(@ViewBuilder label: @escaping () -> Label) { self.label = label }

    public var body: some View {
        HStack(spacing: JISpacing.s2) {
            label()
            Image(systemName: JIChevronRowMetrics.chevron)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.color(.mutedNested))
                .accessibilityHidden(true)
        }
        .foregroundStyle(theme.color(.text))
        .frame(minHeight: JIChevronRowMetrics.minHeight - 2 * JIChevronRowMetrics.verticalPadding)
        .contentShape(Rectangle())
    }
}

public extension JIChevronRow where Label == JIChevronRowLabel {
    /// `JIChevronRow(title: "Settings", value: "Hub synced 07:41", systemImage: "slider.horizontal.3")`.
    init(title: String, value: String? = nil, systemImage: String? = nil, tint: JIColorRole = .info) {
        self.init { JIChevronRowLabel(title: title, value: value, systemImage: systemImage, tint: tint) }
    }
}

/// Icon well + title + muted value — the row's standard label.
public struct JIChevronRowLabel: View {
    let title: String, value: String?, systemImage: String?, tint: JIColorRole
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(title: String, value: String? = nil, systemImage: String? = nil, tint: JIColorRole = .info) {
        self.title = title; self.value = value; self.systemImage = systemImage; self.tint = tint
    }

    public var body: some View {
        HStack(spacing: JISpacing.s3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.color(tint))
                    .frame(width: JIChevronRowMetrics.iconWell, height: JIChevronRowMetrics.iconWell)
                    .background(theme.color(tint).opacity(0.16), in: RoundedRectangle(cornerRadius: JIChevronRowMetrics.iconWellRadius, style: .continuous))
                    .accessibilityHidden(true)
            }
            if JIChevronRowMetrics.stacksValue(typeSize) {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    if let value { valueText(value) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                titleText
                Spacer(minLength: JISpacing.s2)
                if let value { valueText(value) }
            }
        }
        .padding(.vertical, JIChevronRowMetrics.verticalPadding)
    }

    private var titleText: some View {
        Text(title).jiFont(.body).foregroundStyle(theme.color(.text))
            .lineLimit(JIChevronRowMetrics.titleLineLimit(typeSize))
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
            .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
    }

    private func valueText(_ value: String) -> some View {
        Text(value).jiFont(.subheadline).foregroundStyle(theme.color(.muted))
            .lineLimit(JIChevronRowMetrics.titleLineLimit(typeSize))
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
            .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
    }
}

/// W-FIX6 F6-5 — "How JI learns your normal", "How JI calculates balance…": the explainer entry
/// as a disclosure row (report §7 rule 2: a row with a chevron, never a coloured text link),
/// pushing the same `HowWeCalculate` page `HowWeCalculateLink` did.
public struct JIHowWeCalculateRow: View {
    let rowTitle: String, title: String, steps: [HowWeCalculateStep], note: String?
    @Environment(\.jiTheme) private var theme
    public init(_ rowTitle: String, title: String, steps: [HowWeCalculateStep], note: String? = nil) {
        self.rowTitle = rowTitle; self.title = title; self.steps = steps; self.note = note
    }
    public var body: some View {
        NavigationLink {
            ScrollView { HowWeCalculate(title: title, steps: steps, note: note).padding(20) }
                .background(theme.color(.bg))
                .navigationTitle(title)
        } label: {
            JIChevronRow(title: rowTitle, systemImage: "function")
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel(rowTitle)
        .accessibilityIdentifier("how-we-calculate-link")
    }
}
