import SwiftUI
import JIDesign

/// B-33 §5 + §8.2 chrome for the `List`/`Form` screens this lane owns (L6). The explicit
/// the explicit page backgrounds are gone, so the **system grouped background** shows through; the
/// only thing a screen still has to say is "inset grouped", and that style does not exist on
/// macOS (the host the package tests run on), hence the one `#if` here instead of ~15 inline.
///
/// Named for the lane so a parallel Phase-B lane adding its own chrome helper cannot collide.
extension View {
    /// `.listStyle(.insetGrouped)` where the platform has it, a no-op where it does not.
    ///
    /// **`List` only.** A `Form` is already inset grouped on iOS, and forcing the style onto one
    /// deadlocks `ImageRenderer` at accessibility text sizes — the §8.5 sweep hangs instead of
    /// failing (bisected on `CheckInSheet`, B-33 L6). The `Form` screens in this lane therefore
    /// carry no style modifier at all; they only drop their explicit page background (§5).
    func jiNativeFormChrome() -> some View {
        #if os(iOS) || os(visionOS)
        return self.listStyle(.insetGrouped)
        #else
        return self
        #endif
    }

    /// §8.2: sheets are form-sized in regular width instead of full-screen.
    func jiNativeSheetSizing() -> some View {
        #if os(iOS) || os(visionOS) || os(macOS)
        return self.presentationSizing(.form)
        #else
        return self
        #endif
    }
}

// MARK: - B-57 W1 board summary card (fixer f3)

/// The status line under a board card's big number: a glyph + one word, tinted by role.
struct BoardStatus: Equatable {
    var word: String
    var systemImage: String?
    var role: JIColorRole
}

/// The v11 boards' summary card (Streak · Last backup · Mirrored · Sources fresh · WHO-5): icon +
/// title (+ a trailing caption), one big number with its unit, a status word, an optional segment
/// track and a note. It renders as a `List` row (the section is the card). A nil `value` draws
/// "—" in muted — never a zero (rule 5).
struct BoardSummaryCard<Accessory: View>: View {
    let systemImage: String
    let title: String
    var trailing: String? = nil
    let value: String?
    var unit: String? = nil
    var valueTint: JIColorRole = .info
    var status: BoardStatus? = nil
    /// One capsule per item; nil = an empty track slot.
    var segments: [JIColorRole?] = []
    var note: String? = nil
    @ViewBuilder var accessory: Accessory
    @Environment(\.jiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(theme.color(valueTint))
                Text(title).jiFont(.subheadline, weight: .semibold, tint: .text)
                Spacer(minLength: 8)
                if let trailing { Text(trailing).jiFont(.footnote, tint: .muted) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { number; unitText }
                VStack(alignment: .leading, spacing: 2) { number; unitText }
            }
            if let status {
                Label {
                    Text(status.word).jiFont(.subheadline, weight: .semibold)
                } icon: {
                    Image(systemName: status.systemImage ?? "minus")
                }
                .foregroundStyle(theme.color(status.role))
            }
            if !segments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, role in
                        Capsule().fill(role.map { theme.color($0) } ?? theme.color(.control))
                            .frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            if let note { Text(note).jiFont(.subheadline, tint: .text).fixedSize(horizontal: false, vertical: true) }
            accessory
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var number: some View {
        Text(value ?? "—")
            .jiNumeral(.numeralLarge, weight: .bold, tint: value == nil ? .muted : valueTint)
            .lineLimit(1).minimumScaleFactor(0.5)
    }

    @ViewBuilder private var unitText: some View {
        if let unit, value != nil { Text(unit).jiFont(.subheadline, tint: .muted).lineLimit(2) }
    }
}

extension BoardSummaryCard where Accessory == EmptyView {
    init(systemImage: String, title: String, trailing: String? = nil, value: String?, unit: String? = nil,
         valueTint: JIColorRole = .info, status: BoardStatus? = nil, segments: [JIColorRole?] = [], note: String? = nil) {
        self.init(systemImage: systemImage, title: title, trailing: trailing, value: value, unit: unit,
                  valueTint: valueTint, status: status, segments: segments, note: note, accessory: { EmptyView() })
    }
}

/// The Journal / Mind boards' section header: bold, title case, with an optional trailing caption
/// or link ("10 seconds", "Calendar", "WHO-5", "Log an event") — not the system's small caps.
/// Stacks at accessibility sizes instead of clipping (sweep `ax3`).
struct BoardSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText
                Spacer(minLength: 8)
                trailing
            }
            VStack(alignment: .leading, spacing: 2) { titleText; trailing }
        }
        .textCase(nil)
    }

    private var titleText: some View {
        Text(title).jiFont(.cardTitle, weight: .bold, tint: .text).accessibilityAddTraits(.isHeader)
    }
}

/// A muted trailing caption for `BoardSectionHeader` / board rows.
struct BoardCaption: View {
    let text: String
    var body: some View { Text(text).jiFont(.subheadline, tint: .muted) }
}

extension BoardSectionHeader where Trailing == BoardCaption {
    /// A header with a muted trailing caption.
    init(_ title: String, caption: String) {
        self.init(title: title) { BoardCaption(text: caption) }
    }
}

extension BoardSectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}
