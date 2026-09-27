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
            Text(title).jiFont(.body).foregroundStyle(theme.color(.text)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: JISpacing.s2)
            if let value {
                Text(value).jiFont(.subheadline).foregroundStyle(theme.color(.muted)).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, JIChevronRowMetrics.verticalPadding)
    }
}
