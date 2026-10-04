import SwiftUI
import JICore
import JIDesign
import JIPersistence

/// W-B38-A A-11 — History: logged sessions by date → their sets (cache first, then the hub).
public struct StrengthHistoryView: View {
    @Bindable private var model: StrengthHistoryViewModel
    private let theme = JITheme.native

    public init(model: StrengthHistoryViewModel) { self.model = model }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                if let error = model.hubError {
                    Text("Showing what this phone has — \(error)").jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("strength-history-hub-error")
                }
                if model.entries.isEmpty {
                    Surface { Text("No logged sessions yet.").jiFont(.body).foregroundStyle(theme.color(.muted)) }
                        .accessibilityIdentifier("strength-history-empty")
                }
                ForEach(model.entries) { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        JISectionHeader(Self.dateTitle(entry.session.date))
                        Surface(level: 1, padding: JISpacing.cardPadding) {
                            VStack(alignment: .leading, spacing: JISpacing.s3) {
                                HStack {
                                    Text(entry.session.sessionName ?? "Strength session").jiFont(.cardTitle).foregroundStyle(theme.color(.text))
                                    Spacer()
                                    Text(entry.session.isComplete ? "\(entry.setCount) sets" : "\(entry.setCount) sets · open")
                                        .jiFont(.caption).foregroundStyle(theme.color(.muted))
                                }
                                ForEach(entry.exercises) { ex in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.key).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                                        Text(ex.sets.map(StrengthFormat.setLine).joined(separator: "  ·  "))
                                            .jiFont(.caption).foregroundStyle(theme.color(.muted))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("strength-history-\(entry.session.date)")
                }
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiTheme(.native)
        .navigationTitle("Strength history")
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    /// "2026-10-03" → "Sat 3 Oct" (fixed en_US_POSIX parse, the user's locale for display).
    static func dateTitle(_ iso: String) -> String {
        guard iso.count == 10, let day = DayKey(iso: iso) else { return iso } // W-FIX13 F-1
        return day.string(template: "EEE d MMM")
    }
}
